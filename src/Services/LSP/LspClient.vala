using GLib;
using Gee;

[CCode (cheader_filename = "unistd.h")]
extern int getpid ();

public class Iide.LspPromise : Object {
    public SourceFunc callback;
    // Можно добавить время создания для контроля таймаутов
    public int64 creation_time;

    public LspPromise (owned SourceFunc cb) {
        this.callback = (owned) cb;
        this.creation_time = get_monotonic_time ();
    }
}

public enum Iide.TextDocumentSyncKind {
    NONE = 0,
    FULL = 1,
    INCREMENTAL = 2
}

public class Iide.ServerCapabilities : Object {
    public TextDocumentSyncKind sync_kind = TextDocumentSyncKind.FULL;
    public HashSet<string> completion_triggers = new HashSet<string> ();
    public bool hover_provider = false;
    public bool definition_provider = false;

    // To features...
    public bool references_provider = false;
    public bool rename_provider = false;
}

public class Iide.LspClient : Object {
    private int next_id = 1;
    private Map<int, LspPromise> pending_requests = new HashMap<int, LspPromise> ();
    private Map<int, Json.Object?> responses = new HashMap<int, Json.Object?> ();

    // Процесс LSP сервера
    private GLib.Subprocess process;

    // Поток для чтения (стандартный вывод сервера)
    private GLib.DataInputStream input_stream;

    // Поток для записи (стандартный ввод сервера)
    private bool is_writing = false;
    private Deque<string> write_queue = new LinkedList<string> ();
    private OutputStream output_stream;

    // Сигнал для передачи диагностики в UI
    public signal void diagnostics_received (string uri, Json.Array diagnostics);

    // Сигнал для логирования сообщений от сервера
    public signal void log_message (int type, string message);

    // Свойство возможностей сервера
    public ServerCapabilities capabilities { get; private set; }

    public LspClient () {
        this.capabilities = new ServerCapabilities ();
    }

    public async Json.Object? send_request (string method, Json.Object params) throws Error {
        int id = next_id++;

        // 1. Упаковываем запрос
        var root = new Json.Object ();
        root.set_string_member ("jsonrpc", "2.0");
        root.set_int_member ("id", id);
        root.set_string_member ("method", method);
        root.set_object_member ("params", params);

        // 2. Регистрируем обещание (Promise)
        // Мы передаем send_request.callback, который Vala автоматически
        // подготовит для возобновления после yield
        pending_requests.set (id, new LspPromise (send_request.callback));

        // 3. Отправляем (реализацию send_message_async добавим следом)
        yield this.send_message_async (root);

        // 4. Засыпаем до получения ответа
        yield;

        // 5. Просыпаемся и забираем результат
        var response = responses.get (id);
        responses.unset (id);

        return response;
    }

    private async void send_message_async (Json.Object node) throws Error {
        // 1. Подготовка сообщения
        var generator = new Json.Generator ();
        var root_node = new Json.Node (Json.NodeType.OBJECT);
        root_node.set_object (node);
        generator.set_root (root_node);

        string body = generator.to_data (null);
        string message = "Content-Length: %d\r\n\r\n%s".printf ((int) body.length, body);

        // 2. Добавляем в очередь
        write_queue.add (message);

        // 3. Если уже пишем — просто выходим, текущий процесс записи заберет наше сообщение
        if (is_writing)return;

        is_writing = true;

        try {
            while (!write_queue.is_empty) {
                string current_msg = write_queue.poll_head ();
                yield output_stream.write_all_async (current_msg.data, Priority.DEFAULT, null, null);

                yield output_stream.flush_async (Priority.DEFAULT, null);
            }
        } finally {
            is_writing = false;
        }
    }

    private async void run_read_loop () {
        try {
            while (true) {
                // 1. Читаем заголовок Content-Length
                string? line = yield input_stream.read_line_async (Priority.DEFAULT, null);

                if (line == null)break; // Поток закрыт

                if (line.has_prefix ("Content-Length: ")) {
                    int length = int.parse (line.substring (16).strip ());

                    // 2. Пропускаем все остальные заголовки до пустой строки (\r\n\r\n)
                    while (line != "" && line != null) {
                        line = yield input_stream.read_line_async (Priority.DEFAULT, null);

                        if (line != null)line = line.strip ();
                    }

                    // 3. Читаем тело JSON строго по длине
                    uint8[] buffer = new uint8[length + 1];
                    size_t bytes_read;
                    yield input_stream.read_all_async (buffer[0 : length], Priority.DEFAULT, null, out bytes_read);

                    buffer[length] = '\0'; // Гарантируем конец строки для парсера

                    // 4. Обрабатываем полученный пакет
                    this.handle_payload ((string) buffer);
                }
            }
        } catch (Error e) {
            if (!(e is IOError.CANCELLED)) {
                debug ("LSP Read Loop Error: %s", e.message);
            }
        }
    }

    private void handle_payload (string payload) {
        try {
            var parser = new Json.Parser ();
            parser.load_from_data (payload);
            var root = parser.get_root ().get_object ();

            // Это ответ на наш запрос (есть 'id')
            if (root.has_member ("id")) {
                this.handle_response (root);
            }
            // Это уведомление или запрос от сервера (есть 'method', нет 'id')
            else if (root.has_member ("method")) {
                this.handle_incoming_notification (root);
            }
        } catch (Error e) {
            warning ("Failed to parse LSP payload: %s", e.message);
        }
    }

    private void handle_response (Json.Object response) {
        int id = (int) response.get_int_member ("id");

        if (pending_requests.has_key (id)) {
            var promise = pending_requests.get (id);
            pending_requests.unset (id);

            // Сохраняем результат для проснувшегося метода
            responses.set (id, response);

            // Передаем управление обратно в асинхронный метод
            // Используем Idle.add, чтобы вернуться в MainContext (UI поток)
            Idle.add ((owned) promise.callback);
        }
    }

    private void handle_incoming_notification (Json.Object root) {
        string method = root.get_string_member ("method");

        // Уведомления могут не иметь параметров (params)
        Json.Object? params = null;
        if (root.has_member ("params")) {
            params = root.get_object_member ("params");
        }

        switch (method) {
        case "textDocument/publishDiagnostics" :
            if (params != null)handle_diagnostics (params);
            break;

        case "window/logMessage" :
            if (params != null)handle_log_message (params);
            break;

        case "window/showMessage":
            // Здесь можно вызывать всплывающие уведомления в стиле GNOME
            if (params != null)debug ("LSP Show Message: %s", params.get_string_member ("message"));
            break;

        default:
            debug ("Unhandled LSP notification: %s", method);
            break;
        }
    }

    private void handle_diagnostics (Json.Object params) {
        string uri = params.get_string_member ("uri");
        var diagnostics = params.get_array_member ("diagnostics");

        // Пробрасываем данные через сигнал в главный поток
        Idle.add (() => {
            this.diagnostics_received (uri, diagnostics);
            return Source.REMOVE;
        });
    }

    private void handle_log_message (Json.Object params) {
        int type = (int) params.get_int_member ("type");
        string message = params.get_string_member ("message");

        Idle.add (() => {
            this.log_message (type, message);
            return Source.REMOVE;
        });
    }

    public async bool start_server_async (string command, string[] args, string? workspace_root, Json.Node? initialization_options = null) {
        try {
            // 1. Подготовка аргументов запуска
            string[] argv = { command };
            foreach (var arg in args)argv += arg;

            // 2. Запуск подпроцесса
            var launcher = new SubprocessLauncher (SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDIN_PIPE);
            this.process = launcher.spawnv (argv);

            // 3. Инициализация асинхронных потоков
            this.output_stream = this.process.get_stdin_pipe ();
            this.input_stream = new DataInputStream (this.process.get_stdout_pipe ());

            // 4. Запуск цикла чтения (он будет ждать сообщений в фоне)
            this.run_read_loop.begin ();

            // 5. Фаза INITIALIZE
            var init_params = build_init_params (workspace_root, initialization_options);
            var response = yield this.send_request ("initialize", init_params);

            if (response != null && response.has_member ("result")) {
                var result = response.get_object_member ("result");
                // Извлекаем возможности сервера
                this.parse_capabilities (result);
            }

            // 6. Фаза INITIALIZED (уведомление о готовности)
            yield this.send_notification_async ("initialized", new Json.Object ());

            debug ("LSP Server started and initialized for: %s", workspace_root ?? "unknown");
            return true;
        } catch (Error e) {
            warning ("Failed to start LSP server: %s", e.message);
            return false;
        }
    }

    private void parse_capabilities (Json.Object result) {
        if (!result.has_member ("capabilities"))return;
        var caps = result.get_object_member ("capabilities");

        // Синхронизация документа
        if (caps.has_member ("textDocumentSync")) {
            var sync = caps.get_member ("textDocumentSync");
            if (sync.get_node_type () == Json.NodeType.OBJECT) {
                var sync_obj = sync.get_object ();
                if (sync_obj.has_member ("change"))
                    this.capabilities.sync_kind = (TextDocumentSyncKind) sync_obj.get_int_member ("change");
            } else if (sync.get_node_type () == Json.NodeType.VALUE) {
                this.capabilities.sync_kind = (TextDocumentSyncKind) sync.get_int ();
            }
        }

        // Триггеры автодополнения
        if (caps.has_member ("completionProvider")) {
            var comp = caps.get_object_member ("completionProvider");
            if (comp.has_member ("triggerCharacters")) {
                var triggers = comp.get_array_member ("triggerCharacters");
                this.capabilities.completion_triggers.clear ();
                foreach (var node in triggers.get_elements ()) {
                    this.capabilities.completion_triggers.add (node.get_string ());
                }
            }
        }

        // Hover & Definition
        this.capabilities.hover_provider = caps.has_member ("hoverProvider") && caps.get_boolean_member ("hoverProvider");
        this.capabilities.definition_provider = caps.has_member ("definitionProvider") && caps.get_boolean_member ("definitionProvider");
    }

    private Json.Object build_init_params (string? root_uri, Json.Node? options) {
        var params = new Json.Object ();
        params.set_int_member ("processId", getpid ());
        params.set_string_member ("rootUri", root_uri ?? "");

        var client_caps = new Json.Object (); // Здесь можно объявить, что наш клиент умеет (Markdown и т.д.)
        params.set_object_member ("capabilities", client_caps);

        if (options != null && options.get_node_type () == Json.NodeType.OBJECT) {
            params.set_object_member ("initializationOptions", options.get_object ());
        }
        return params;
    }

    public async void send_notification_async (string method, Json.Object params) throws Error {
        var root = new Json.Object ();
        root.set_string_member ("jsonrpc", "2.0");
        root.set_string_member ("method", method);
        root.set_object_member ("params", params);

        // Вызываем наш атомарный метод записи в поток
        yield this.send_message_async (root);
    }
}
