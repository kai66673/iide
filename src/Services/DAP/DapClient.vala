/*
*/
public enum Iide.DapClientStatus {
    STOPPED,
    STARTING,
    INITIALIZING,
    READY,
    FAILED
}

public class Iide.DapClient : GLib.Object {
    // Полиморфный интерфейс транспорта (может быть RpcProcess или TcpProcess!)
    private Iide.RpcTransport? transport = null;
    private Iide.DapConfig config;

    public DapClientStatus status { get; set; default = DapClientStatus.STOPPED; }
    private bool is_stopping = false;
    private LoggerService logger;

    // Внутреннее ведение ID-запросов по вашей эталонной схеме обещаний
    private int request_id = 0;
    private Gee.HashMap<int, LspPromise> pending_requests = new Gee.HashMap<int, LspPromise> ();
    private Gee.HashMap<int, Json.Object> responses = new Gee.HashMap<int, Json.Object> ();

    // Сигналы DAP-клиента для вывода логов и перехвата событий отладчика в UI
    public signal void log_received (string type_label, string message);
    public signal void stopped_on_breakpoint (int thread_id, string reason); // Когда код замер на точке!
    public signal void thread_event (string reason, int thread_id);
    public signal void terminated ();
    public signal void adapter_ready_for_configuration ();

    public DapClient (Iide.DapConfig config) {
        Object ();
        this.config = config;
        this.logger = LoggerService.get_instance ();
    }

    public string name () { return this.config.id; }

    /**
     * 1. ФИЗИЧEСКИЙ СТАРТ АДАПТEРА С ДИНАМИЧEСКОЙ ФАБРИКOЙ ТРАНСПOРТА
     */
    public async bool start_adapter_process_async (string? workspace_root) {
        if (this.status != DapClientStatus.STOPPED && this.status != DapClientStatus.FAILED) return false;
        this.status = DapClientStatus.STARTING;
        this.is_stopping = false;

        // ДИНАМИЧЕСКИЙ ВЫБОР ДВИЖКА ТРАНСПОРТА!
        if (this.config.transport == "tcp") {
            this.transport = new Iide.TcpProcess (); 
        } else {
            // Используем наш универсальный переименованный RpcProcess
            this.transport = new Iide.RpcProcess ();
        }

        // Биндим сигналы транспорта на методы нашего семантического ядра
        this.transport.message_received.connect (this.handle_payload);
        this.transport.stderr_received.connect ((line) => {
            this.log_received ("STDERR", line);
        });
        this.transport.unexpected_crash.connect (() => {
            if (!this.is_stopping) {
                this.status = DapClientStatus.FAILED;
                this.terminated ();
            }
        });

        // Инициализируем физический запуск (stdio спавн или tcp коннект)
        bool success = this.transport.init_channel (this.config.command, workspace_root);
        if (!success) {
            this.status = DapClientStatus.FAILED;
            this.transport = null;
            return false;
        }

        this.status = DapClientStatus.INITIALIZING;
        return true;
    }

    /**
     * 2. ФАЗА ХЭНДШEЙКА: ИНИЦИАЛИЗАЦИЯ DAP СEССИИ
     */
    public async bool send_initialize_request () throws GLib.Error {
        var params = new Json.Object ();
        params.set_string_member ("clientID", "iide");
        params.set_string_member ("clientName", "IIDE Editor");
        params.set_string_member ("adapterID", this.config.id);
        params.set_string_member ("pathFormat", "path");
        params.set_boolean_member ("linesStartAt1", true);
        params.set_boolean_member ("columnsStartAt1", true);
        params.set_boolean_member ("supportsVariableType", true);
        params.set_boolean_member ("supportsRunInTerminalRequest", false);

        this.logger.info ("DAP", "Sending 'initialize' request to debug adapter...");
        var reply = yield this.send_request ("initialize", params);
        
        if (reply != null && reply.has_member ("success") && reply.get_boolean_member ("success")) {
            this.logger.info ("DAP", "Debug adapter initialized successfully.");
            return true;
        }
        return false;
    }

    /**
     * RPC-ЗАПРОС ЗАВEРШEНИЯ КОНФИГУРАЦИИ (LSP/DAP configurationDone)
     * Сигнализирует отладчику, что все стартовые настройки и брейкпоинты переданы,
     * и можно запускать физическое выполнение кода скрипта!
     */
    public async bool send_configuration_done_request () throws GLib.Error {
        this.logger.info ("DAP", "Sending 'configurationDone' to trigger execution loop...");
        
        // Запрос configurationDone по спецификации не требует аргументов (null)
        var reply = yield this.send_request ("configurationDone", null);
        
        if (reply != null && reply.has_member ("success")) {
            return reply.get_boolean_member ("success");
        }
        return false;
    }

    /**
     * 3. ЗАПУСК ОTЛАЖИВАEМOГO СКРИПTА (ПEРEДАЧА launch.json КОНФИГУРАЦИИ)
     */
    public async bool send_launch_request (Json.Object processed_target_args) throws GLib.Error {
        this.logger.info ("DAP", "Sending 'launch' target configuration payload...");
        this.logger.debug ("DAP", "laaunch with: %s".printf (json_object_to_string (processed_target_args)));
        
        // В DAP параметры запуска передаются в корне объекта 'arguments' запроса launch
        var reply = yield this.send_request ("launch", processed_target_args);
        
        if (reply != null && reply.has_member ("success") && reply.get_boolean_member ("success")) {
            this.status = DapClientStatus.READY;
            return true;
        }
        
        this.status = DapClientStatus.FAILED;
        return false;
    }

    /**
     * ЦЕНТРАЛЬНЫЙ СEМАНТИЧEСКИЙ RPC-ОТПРАВИТEЛЬ С ПОДДEРЖКOЙ CANCELLABLE
     */
    public async Json.Object? send_request (string command, Json.Object? arguments, Cancellable? cancellable = null) throws GLib.Error {
        if (this.transport == null) return null;

        int id = ++this.request_id;
        
        // В протоколе DAP вместо слова "method" используется слово "command"!
        var root = new Json.Object ();
        root.set_string_member ("type", "request");
        root.set_int_member ("seq", id); // В DAP вместо поля "id" используется "seq" (sequence)!
        root.set_string_member ("command", command);
        
        if (arguments != null) {
            root.set_object_member ("arguments", arguments); // В DAP вместо "params" используется "arguments"!
        }

        var generator = new Json.Generator ();
        var root_node = new Json.Node (Json.NodeType.OBJECT);
        root_node.set_object (root);
        generator.set_root (root_node);
        string body = generator.to_data (null);

        var promise = new LspPromise (send_request.callback);
        this.pending_requests.set (id, promise);

        ulong handler_id = 0;
        if (cancellable != null) {
            handler_id = cancellable.connect (() => {
                if (this.pending_requests.has_key (id)) {
                    this.pending_requests.unset (id);
                    Idle.add ((owned) promise.callback);
                }
            });
        }

        try {
            // Толкаем сериализованный JSON в наш абстрактный RpcTransport!
            yield this.transport.write_message_async (body);
            yield; // Спим до прилета ответа сокетов в handle_payload

            if (cancellable != null && cancellable.is_cancelled ()) {
                throw new IOError.CANCELLED ("DAP Request %s (seq: %d) was cancelled.".printf (command, id));
            }

            var response = this.responses.get (id);
            this.responses.unset (id);
            return response;
        } finally {
            if (handler_id > 0) cancellable.disconnect (handler_id);
        }
    }

    /**
     * ПРИEМЩИК СЫРЫХ ПАКEТОВ: ПАРСИНГ СПEЦИФИКИ DAP (Requests / Responses / Events)
     */
    private void handle_payload (string payload) {
        var parser = new Json.Parser ();
        try {
            parser.load_from_data (payload, -1);
            var root = parser.get_root ().get_object ();

            if (!root.has_member ("type")) return;
            string type = root.get_string_member ("type");

            // Сценарий А: Это ответ на наш запрос (type == "response")
            if (type == "response") {
                // В DAP ответ возвращает ID нашего запроса в поле "request_seq"
                int request_seq = (int) root.get_int_member ("request_seq");
                
                if (this.pending_requests.has_key (request_seq)) {
                    this.responses.set (request_seq, root);
                    var promise = this.pending_requests.get (request_seq);
                    this.pending_requests.unset (request_seq);
                    
                    // Будим уснувший метод send_request в UI-потоке!
                    promise.callback ();
                }
                return;
            }

            // Сценарий Б: Это встречное асинхронное событие от отладчика (type == "event")
            if (type == "event") {
                this.handle_incoming_dap_event (root);
            }
        } catch (GLib.Error e) {
            this.logger.error ("DAP", "DAP JSON parse error: " + e.message);
        }
    }

    /**
     * ПАРСИНГ СОБЫТИЙ ОТЛАДЧИКА (Брейкпоинты, Выход, Потоки)
     */
    private void handle_incoming_dap_event (Json.Object root) {
        string event_name = root.get_string_member ("event");
        var body = root.has_member ("body") ? root.get_object_member ("body") : null;

        switch (event_name) {
            case "initialized":
                this.logger.info ("DAP", "Received 'initialized' event from adapter. Signaling service to push configuration...");
                // Стреляем сигналом наверх, выводя систему из ступора! [INDEX]
                Idle.add (() => {
                    this.adapter_ready_for_configuration ();
                    return Source.REMOVE;
                });
                break;
            
            // Самое главное событие DAP: Отладчик наткнулся на точку останова!
            case "stopped":
                if (body != null) {
                    string reason = body.get_string_member ("reason"); // "breakpoint", "step", "exception"
                    int thread_id = body.has_member ("threadId") ? (int) body.get_int_member ("threadId") : 0;
                    this.logger.warning ("DAP", @"!!! DEBUGGER STOPPED !!! Reason: $reason on Thread $thread_id");
                    // Стреляем сигналом наружу, чтобы UI за подсветил текущую строку файла желтым!
                    this.stopped_on_breakpoint (thread_id, reason);
                }
                break;
            case "thread":
                if (body != null) {
                    string reason = body.get_string_member ("reason"); // "started", "exited"
                    int thread_id = (int) body.get_int_member ("threadId");
                    this.thread_event (reason, thread_id);
                }
                break;
            case "terminated":
                this.logger.info ("DAP", "Debug session terminated by adapter backend.");
                this.status = DapClientStatus.STOPPED;
                this.terminated ();
                break;
            }
        }

    /**
     * КОМАНДА: ПРОДОЛЖИТЬ ВЫПОЛНEНИE (Continue / F5 на паузе)
     * Говорит отладчику отпустить программу до следующего брейкпоинта
     */
    public async bool request_continue (int thread_id) throws GLib.Error {
        var arguments = new Json.Object ();
        arguments.set_int_member ("threadId", thread_id);

        this.logger.info ("DAP", @"Sending 'continue' request for Thread $thread_id...");
        var reply = yield this.send_request ("continue", arguments);

        if (reply != null && reply.has_member ("success")) {
            return reply.get_boolean_member ("success");
        }
        return false;
    }

    /**
     * КОМАНДА: ШАГ ЧEРEЗ (Step Over / F10 / Next)
     * Выполняет текущую строку без захода внутрь вызываемых функций
     */
    public async bool request_step_over (int thread_id) throws GLib.Error {
        var arguments = new Json.Object ();
        arguments.set_int_member ("threadId", thread_id);

        this.logger.info ("DAP", @"Sending 'next' (Step Over) request for Thread $thread_id...");
        var reply = yield this.send_request ("next", arguments); // В DAP метод называется "next"

        if (reply != null && reply.has_member ("success")) {
            return reply.get_boolean_member ("success");
        }
        return false;
    }

    /**
     * КОМАНДА: ШАГ ВНУТРЬ (Step Into / F11 / StepIn)
     * Заходит внутрь функции, если она вызывается на текущей строке
     */
    public async bool request_step_into (int thread_id) throws GLib.Error {
        var arguments = new Json.Object ();
        arguments.set_int_member ("threadId", thread_id);

        this.logger.info ("DAP", @"Sending 'stepIn' (Step Into) request for Thread $thread_id...");
        var reply = yield this.send_request ("stepIn", arguments);

        if (reply != null && reply.has_member ("success")) {
            return reply.get_boolean_member ("success");
        }
        return false;
    }

    /**
     * КОМАНДА: ШАГ НАРУЖУ (Step Out / Shift+F11 / StepOut)
     * Выполняет код до выхода из текущей функции
     */
    public async bool request_step_out (int thread_id) throws GLib.Error {
        var arguments = new Json.Object ();
        arguments.set_int_member ("threadId", thread_id);

        this.logger.info ("DAP", @"Sending 'stepOut' (Step Out) request for Thread $thread_id...");
        var reply = yield this.send_request ("stepOut", arguments);

        if (reply != null && reply.has_member ("success")) {
            return reply.get_boolean_member ("success");
        }
        return false;
    }
    
    /*** Атомарное тушение сессии отладки*/
    public async void disconnect_and_stop_async () {
        if (this.transport == null)
            return;
        
        this.is_stopping = true;
        try {
            // Шлем протокольный запрос завершения сессии
            var params = new Json.Object ();
            params.set_boolean_member ("terminateDebuggee", true);
            
            // Прибиваем отлаживаемый Python скрипт вместе с сессией!
            yield this.send_request ("disconnect", params);
        } catch {

        }
        
        yield this.transport.terminate_async ();
        this.transport = null;
        this.pending_requests.clear ();
        this.responses.clear ();
        this.status = DapClientStatus.STOPPED;
        this.is_stopping = false;
    }

    /**
     * RPC-ЗАПРОС УСТАНОВКИ БРEЙКПОИНТОВ ДЛЯ КОНКРEТНОГО ФАЙЛА (LSP/DAP textDocument/setBreakpoints)
     * Отправляет массив всех строк останова для указанного URI [INDEX]
     */
    public async bool request_set_breakpoints (string uri, Gee.ArrayList<int> lines) throws GLib.Error {
        if (this.transport == null || 
            this.status == DapClientStatus.STOPPED || 
            this.status == DapClientStatus.FAILED) {
            this.logger.warning ("DAP", "Aborting setBreakpoints: transport is dead or client is stopped.");
            return false;
        }

        var arguments = new Json.Object ();

        // 1. Указываем спецификацию источника (source) по стандарту DAP
        var source_obj = new Json.Object ();
        // DAP работает с абсолютными системными путями, поэтому убираем "file://" префикс [INDEX]
        string clean_path = uri.replace ("file://", "");
        source_obj.set_string_member ("path", clean_path);
        source_obj.set_string_member ("name", Path.get_basename (clean_path));
        arguments.set_object_member ("source", source_obj);

        // 2. Собираем массив строк останова
        var lines_array = new Json.Array ();
        var bp_array = new Json.Array ();

        foreach (int line_idx in lines) {
            // ВАЖНО: В TextLineMarkService строки хранятся 0-indexed (как в GTK) [INDEX]
            // Но спецификация DAP требует строго 1-based индексацию строк! Делаем +1 [INDEX]
            int dap_line = line_idx + 1;
            
            lines_array.add_int_element (dap_line);

            // Формируем массив объектов SourceBreakpoint для расширенных свойств
            var source_bp_obj = new Json.Object ();
            source_bp_obj.set_int_member ("line", dap_line);
            bp_array.add_object_element (source_bp_obj);
        }

        arguments.set_array_member ("lines", lines_array);
        arguments.set_array_member ("breakpoints", bp_array); // Требование некоторых строгих адаптеров

        this.logger.info ("DAP", @"Sending 'setBreakpoints' for file: $clean_path ($(lines.size) points)...");
        
        // Стреляем запросом в сокет отладчика
        var reply = yield this.send_request ("setBreakpoints", arguments);

        if (reply != null && reply.has_member ("success") && reply.get_boolean_member ("success")) {
            this.logger.debug ("DAP", @"Breakpoints for $clean_path successfully synchronized with server.");
            return true;
        }
        return false;
    }
}