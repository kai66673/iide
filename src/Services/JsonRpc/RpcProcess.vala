/*
*/

public class Iide.RpcProcess : GLib.Object, RpcTransport {
    private GLib.Subprocess? process = null;
    
    private GLib.OutputStream? output_stream = null;
    private GLib.DataInputStream? input_stream = null;
    private GLib.DataInputStream? stderr_stream = null;
    
    // Индивидуальный токен отмены для ЭТОГО конкретного запуска процесса ОС
    private GLib.Cancellable read_cancellable;
    
    // Индивидуальная FIFO-очередь мьютекса отправки байт
    private Gee.Deque<RpcWriteTask> write_waiters;
    private bool is_writing = false;

    // Счетчик активных фоновых циклов для асинхронного барьера
    private int active_loops_count = 0;
    private SourceFunc? shutdown_barrier_callback = null;

    public RpcProcess () {
        Object ();
        this.read_cancellable = new GLib.Cancellable ();
        this.write_waiters = new Gee.ArrayQueue<RpcWriteTask> ();
    }

    /**
     * ФИЗИЧЕСКИЙ СПАВН ПРОЦЕССА В ОПЕРАЦИОННОЙ СИСТЕМЕ
     */
    public bool init_channel (string[] command, string? workspace_root) {
        try {
            var launcher = new SubprocessLauncher (
                SubprocessFlags.STDOUT_PIPE | 
                SubprocessFlags.STDIN_PIPE | 
                SubprocessFlags.STDERR_PIPE
            );
            
            if (workspace_root != null && workspace_root != "") {
                launcher.set_cwd (workspace_root.replace ("file://", ""));
            }
            
            this.process = launcher.spawnv (command);

            // Захватываем низкоуровневые дескрипторы пайпов ОС
            this.output_stream = this.process.get_stdin_pipe ();
            this.input_stream = new DataInputStream (this.process.get_stdout_pipe ());
            this.stderr_stream = new DataInputStream (this.process.get_stderr_pipe ());

            // Сбрасываем барьер и лениво запускаем два фоновые потока чтения в режиме fire-and-forget
            this.active_loops_count = 0;
            this.run_stdout_loop.begin ();
            this.run_stderr_loop.begin ();
            
            return true;
        } catch (GLib.Error e) {
            LoggerService.get_instance ().error ("LSP-PROCESS", "Failed to spawn OS sub-process: " + e.message);
            return false;
        }
    }

    /**
        * ПОТОКОБЕЗОПАСНАЯ FIFO-ОТПРАВКА СЫРЫХ БАЙТ
        */
    public async void write_message_async (string payload) throws GLib.Error {
        if (this.output_stream == null || this.output_stream.is_closed ()) {
            throw new IOError.CLOSED ("Cannot write to a closed stream.");
        }

        // Упаковываем строку и колбэк текущего проснувшегося метода в одну атомарную задачу
        var task = new Iide.RpcWriteTask (payload, write_message_async.callback);
        this.write_waiters.offer_tail (task);

        // Если конвейер отправки сейчас спит — будим его!
        if (!this.is_writing) {
            this.process_write_queue.begin ();
        }
        
        yield; // Текущий вызов засыпает и проснется строго по цепочке, когда байты уйдут в сеть
    }

    /**
     * ВНУТРЕННИЙ ФОНОВЫЙ ЦИКЛ ОПУСТОШЕНИЯ ОЧЕРЕДИ ОТПРАВКИ
     */
    private async void process_write_queue () {
        this.is_writing = true;
        
        while (!this.write_waiters.is_empty) {
            var task = this.write_waiters.poll_head ();
            
            try {
                // ТЕПЕРЬ ПАРАМЕТР НА МЕСТЕ: Извлекаем строку из контекста задачи!
                string current_payload = task.payload;
                
                // Формируем честный RPC-чанк с Content-Length
                string raw_packet = "Content-Length: %d\r\n\r\n%s".printf (current_payload.length, current_payload);
                uint8[] data = raw_packet.data;
                
                size_t bytes_written;
                // Передаем токен отмены, индивидуальный для этого запуска процесса ОС
                yield this.output_stream.write_all_async (data, Priority.DEFAULT, this.read_cancellable, out bytes_written);
            } catch (GLib.Error e) {
                LoggerService.get_instance ().error ("LSP-PROCESS", "Write error inside channel: " + e.message);
            } finally {
                // Обязательно возвращаем выполнение вызвавшему методу, продвигая очередь дальше
                Idle.add (() => {
                    task.resume ();
                    return Source.REMOVE;
                });           
            }
        }
        
        this.is_writing = false;
    }

    /**
     * ЖЕЛЕЗОБЕТОННЫЙ ДВУХФАЗНЫЙ БАРЬЕР ТУШЕНИЯ СОКЕТОВ
     */
    public async void terminate_async () {
        LoggerService.get_instance ().debug ("LSP-PROCESS", "Sending cancellation token to background loops...");
        
        // 1. Шлем прерывание во все висящие операции чтения read_line_async
        this.read_cancellable.cancel ();

        // 2. Входим в асинхронный затвор: если потоки чтения еще шевелятся — засыпаем
        if (this.active_loops_count > 0) {
            this.shutdown_barrier_callback = terminate_async.callback;
            yield; 
        }

        LoggerService.get_instance ().debug ("LSP-PROCESS", "All background readers are dead. Safe to close file descriptors.");

        // 3. Теперь закрытие на 100% стерильно. Ни одной outstanding операции нет в природе!
        try {
            if (this.output_stream != null && !this.output_stream.is_closed ()) yield this.output_stream.close_async (Priority.DEFAULT, null);
            if (this.input_stream != null && !this.input_stream.is_closed ()) yield this.input_stream.close_async (Priority.DEFAULT, null);
            if (this.stderr_stream != null && !this.stderr_stream.is_closed ()) yield this.stderr_stream.close_async (Priority.DEFAULT, null);
            
            if (this.process != null) {
                this.process.force_exit (); // Принудительно выгружаем зомби из ОС
            }
        } catch (GLib.Error e) {
            debug ("LSP-PROCESS streams close error: %s", e.message);
        }

        this.write_waiters.clear ();
    }

    /**
        * Поток чтения протокольного STDOUT
        */
    private async void run_stdout_loop () {
        this.active_loops_count++;
        bool crashed_detected = false;

        try {
            while (true) {
                string? line = yield this.input_stream.read_line_async (Priority.DEFAULT, this.read_cancellable);
                if (line == null) {
                    // Поток закрылся со стороны ОС без команды завершения — это крах!
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
                    
                    // Стреляем чистым сигналом наверх в LspClient!
                    Idle.add (() => {
                        this.message_received (payload);
                        return Source.REMOVE; // Выполнить строго один раз
                    });
                }
            }
        } catch (GLib.Error e) {
            if (!(e is IOError.CANCELLED) && !this.read_cancellable.is_cancelled ()) crashed_detected = true;
        } finally {
            this.active_loops_count--;
            this.check_barrier_release ();

            if (crashed_detected) {
                this.unexpected_crash ();
            }
        }
    }

    /**
     * Поток чтения низкоуровневого STDERR
     */
    private async void run_stderr_loop () {
        this.active_loops_count++;
        try {
            while (!this.read_cancellable.is_cancelled ()) {
                string? log_line = yield this.stderr_stream.read_line_async (Priority.DEFAULT, this.read_cancellable);
                if (log_line == null) break;

                log_line = log_line.strip ();
                if (log_line == "") continue;

                string log_line_copy = log_line;
                Idle.add (() => {
                    this.stderr_received (log_line_copy);
                    return Source.REMOVE;
                });
            }
        } catch {
            // Игнорируем отмену GIO
        } finally {
            this.active_loops_count--;
            this.check_barrier_release ();
        }
    }

    private void check_barrier_release () {
        if (this.active_loops_count == 0 && this.shutdown_barrier_callback != null) {
            Idle.add ((owned) this.shutdown_barrier_callback);
            this.shutdown_barrier_callback = null;
        }
    }
}
