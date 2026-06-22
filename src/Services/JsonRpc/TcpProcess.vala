/*
*/
public class Iide.TcpProcess : GLib.Object, RpcTransport {
    private GLib.SocketConnection? connection = null;
    private GLib.OutputStream? output_stream = null;
    private GLib.DataInputStream? input_stream = null;

    // Индивидуальный токен отмены для ЭТОЙ сетевой сессии сокета
    private GLib.Cancellable read_cancellable;

    // FIFO-очередь мьютекса отправки байт через сокет
    private Gee.Deque<RpcWriteTask> write_waiters;
    private bool is_writing = false;

    // Счетчик активных фоновых циклов для асинхронного барьера закрытия
    private int active_read_loops_count = 0;
    private SourceFunc? shutdown_barrier_callback = null;

    // Реализация сигналов интерфейса RpcTransport [INDEX]
    // (Они подхватятся DapClient.vala автоматически)

    public TcpProcess () {
        Object ();
        this.read_cancellable = new GLib.Cancellable ();
        this.write_waiters = new Gee.ArrayQueue<RpcWriteTask> ();
    }

    /**
        * РEАЛИЗАЦИЯ МEТОДА ИНТEРФEЙСА RpcTransport
        * Асинхронное подключение к TCP-порту отладочного адаптера
        */
    public bool init_channel (string[] command, string? workspace_root) {
        // Парсим хост и порт из параметров (например, "127.0.0.1:5678" или просто порт)
        string address_str = (command.length > 0) ? command[0] : "127.0.0.1:5678";
        string host = "127.0.0.1";
        uint16 port = 5678;

        if (address_str.contains (":")) {
            var parts = address_str.split (":", 2);
            host = parts[0];
            port = (uint16) int.parse (parts[1]);
        } else if (address_str.length > 0 && int.parse(address_str) > 0) {
            port = (uint16) int.parse (address_str);
        }

        // Запускаем асиннадцатый коннект сокета в фоновом MainContext
        this.connect_socket_async.begin (host, port, (obj, res) => {
            try {
                this.connect_socket_async.end (res);
            } catch (GLib.Error e) {
                LoggerService.get_instance ().error ("TCP-TRANSPORT", "Connection transaction failed: " + e.message);
                this.unexpected_crash (); // Оповещаем DapClient о сбое коннекта
            }
        });

        return true; // Возвращаем true, сигнализируя о начале инициализации канала
    }

    private async void connect_socket_async (string host, uint16 port) throws GLib.Error {
        LoggerService.get_instance ().info ("TCP-TRANSPORT", @"Connecting to debug adapter at $host:$port...");

        var client = new GLib.SocketClient ();
        // Устанавливаем таймаут подключения в 5 секунд, чтобы IDE не зависла вечно
        client.set_timeout (5); 

        // Физический асинхронный коннект по сети [INDEX]
        this.connection = yield client.connect_to_host_async (host, port, this.read_cancellable);
        
        // Вытаскиваем стандартные Си-потоки ввода-вывода из сетевого сокета connections! [INDEX]
        this.output_stream = this.connection.get_output_stream ();
        this.input_stream = new DataInputStream (this.connection.get_input_stream ());

        LoggerService.get_instance ().info ("TCP-TRANSPORT", "Network TCP channel established successfully.");

        // Запускаем фоновый поток чтения RPC-чанков
        this.active_read_loops_count = 0;
        this.run_network_read_loop.begin ();
    }

    /**
        * ПОТОКОБЕЗОПАСНАЯ FIFO-ОТПРАВКА СЫРЫХ БАЙТ В СЕТЕВОЙ СОКЕТ
        */
    public async void write_message_async (string payload) throws GLib.Error {
        if (this.output_stream == null || this.output_stream.is_closed ()) {
            throw new IOError.CLOSED ("Cannot write to a closed TCP socket.");
        }

        var task = new RpcWriteTask (payload, write_message_async.callback);
        this.write_waiters.offer_tail (task);

        if (!this.is_writing) {
            this.process_network_write_queue.begin ();
        }
        yield;
    }

    private async void process_network_write_queue () {
        this.is_writing = true;
        while (!this.write_waiters.is_empty) {
            var task = this.write_waiters.poll_head ();
            try {
                string current_payload = task.payload;
                string raw_packet = "Content-Length: %d\r\n\r\n%s".printf (current_payload.length, current_payload);
                uint8[] data = raw_packet.data;
                
                size_t bytes_written;
                // Пушим байты по сети через write_all_async сокета [INDEX]
                yield this.output_stream.write_all_async (data, Priority.DEFAULT, this.read_cancellable, out bytes_written);
            } catch (GLib.Error e) {
                LoggerService.get_instance ().error ("TCP-TRANSPORT", "Network write failed: " + e.message);
            } finally {
                // Возвращаем управление в UI-поток
                Idle.add (() => {
                    task.resume ();
                    return Source.REMOVE;
                });
            }
        }
        this.is_writing = false;
    }

    /**
        * АТОМАРНЫЙ БАРЬЕР ТУШЕНИЯ СЕТЕВЫХ СТРИМОВ (0% Outstanding-операций)
        */
    public async void terminate_async () {
        LoggerService.get_instance ().debug ("TCP-TRANSPORT", "Cancelling network read operations...");
        this.read_cancellable.cancel ();

        // Асинхронный затвор: ждем, пока фоновый читатель сети полностью выйдет из цикла
        if (this.active_read_loops_count > 0) {
            this.shutdown_barrier_callback = terminate_async.callback;
            yield;
        }

        LoggerService.get_instance ().debug ("TCP-TRANSPORT", "Safe to close network sockets cleanly.");

        try {
            if (this.output_stream != null && !this.output_stream.is_closed ()) yield this.output_stream.close_async (Priority.DEFAULT, null);
            if (this.input_stream != null && !this.input_stream.is_closed ()) yield this.input_stream.close_async (Priority.DEFAULT, null);
            if (this.connection != null && !this.connection.is_closed ()) yield this.connection.close_async (Priority.DEFAULT, null);
        } catch (GLib.Error e) {
            debug ("TCP socket close error: %s", e.message);
        }

        this.write_waiters.clear ();
    }

    /**
        * НАШ ЭТАЛОННЫЙ ЦИКЛ ПАРСИНГА CONTENT-LENGTH ДЛЯ СЕТЕВЫХ ПАКЕТОВ
        */
    private async void run_network_read_loop () {
        this.active_read_loops_count++;
        bool crashed_detected = false;

        try {
            while (true) {
                string? line = yield this.input_stream.read_line_async (Priority.DEFAULT, this.read_cancellable);
                if (line == null) {
                    // Сокет закрылся со стороны сервера без команды exit — потеря связи!
                    if (!this.read_cancellable.is_cancelled ()) crashed_detected = true;
                    break;
                }

                line = line.strip ();
                if (line.has_prefix ("Content-Length:")) {
                    int content_length = int.parse (line.replace ("Content-Length:", "").strip ());
                    
                    // Пропускаем пустую строку разделителя \r\n\r\n
                    yield this.input_stream.read_line_async (Priority.DEFAULT, this.read_cancellable);

                    uint8[] buffer = new uint8[content_length + 1];
                    size_t bytes_read;
                    yield this.input_stream.read_all_async (buffer[0:content_length], Priority.DEFAULT, this.read_cancellable, out bytes_read);
                    buffer[content_length] = 0;

                    string payload = (string) buffer;
                    
                    // Изолированно пробрасываем сырой JSON-текст в UI поток! [INDEX]
                    Idle.add (() => {
                        this.message_received (payload);
                        return Source.REMOVE;
                    });
                }
            }
        } catch (GLib.Error e) {
            if (!(e is IOError.CANCELLED) && !this.read_cancellable.is_cancelled ()) crashed_detected = true;
        } finally {
            this.active_read_loops_count--;
            this.check_barrier_release ();

            if (crashed_detected) {
                // Выстреливаем в UI-поток
                Idle.add (() => {
                    this.unexpected_crash ();
                    return Source.REMOVE;
                });
            }
        }
    }

    private void check_barrier_release () {
        if (this.active_read_loops_count == 0 && this.shutdown_barrier_callback != null) {
            Idle.add ((owned) this.shutdown_barrier_callback);
            this.shutdown_barrier_callback = null;
        }
    }
}
