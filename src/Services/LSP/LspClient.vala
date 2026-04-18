using GLib;
using Gee;

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
    private int next_id = 0;
    private Map<int, LspPromise> pending_requests = new HashMap<int, LspPromise> ();
    private Map<int, Json.Object?> responses = new HashMap<int, Json.Object?> ();
    private LspConfig config;

    // Процесс LSP сервера
    private GLib.Subprocess process;

    // Поток для чтения (стандартный вывод сервера)
    private GLib.DataInputStream input_stream;

    // Поток для записи (стандартный ввод сервера)
    private bool is_writing = false;
    private Deque<string> write_queue = new LinkedList<string> ();
    private OutputStream output_stream;

    // Сигнал для передачи диагностики в UI
    public signal void diagnostics_received (string uri, Gee.ArrayList<IdeLspDiagnostic> diagnostics);

    // Сигнал для логирования сообщений от сервера
    public signal void log_message (int type, string message);

    // Свойство возможностей сервера
    public ServerCapabilities capabilities { get; private set; }

    // Сигнал, сообщающий, что возможности сервера получены и распарсены
    public signal void initialized_with_capabilities (ServerCapabilities caps);

    public bool is_initialized { get; private set; default = false; }

    public LspClient (LspConfig config) {
        this.capabilities = new ServerCapabilities ();
        this.config = config;
    }

    public async Json.Object? send_request (string method, Json.Object params) throws Error {
        int id = next_id--;

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

    public async void send_response_async (Json.Node id, Json.Node? result = null) throws Error {
        var root = new Json.Object ();
        root.set_string_member ("jsonrpc", "2.0");
        root.set_member ("id", id);

        // В ответах используется поле 'result' вместо 'method' и 'params'
        if (result != null) {
            root.set_member ("result", result);
        } else {
            root.set_member ("result", new Json.Node (Json.NodeType.NULL));
        }

        var generator = new Json.Generator ();
        var root_node = new Json.Node (Json.NodeType.OBJECT);
        root_node.set_object (root);
        generator.set_root (root_node);
        message ("!!!send_response_async: " + generator.to_data (null));

        yield this.send_message_async (root);
    }

    private void handle_payload (string payload) {
        try {
            var parser = new Json.Parser ();
            parser.load_from_data (payload);
            var root = parser.get_root ().get_object ();

            if (root.has_member ("method")) {
                message ("!!!handle_payload 01");
                string method = root.get_string_member ("method");
                message ("!!!handle_payload 02: " + method);
                if (method == "window/workDoneProgress/create" && root.has_member ("id")) {
                    // Мы просто подтверждаем, что готовы принимать прогресс с этим токеном
                    message ("!!!handle_payload 02: window/workDoneProgress/create" + json_object_to_string (root));
                    var node_id = root.get_member ("id");
                    send_response_async.begin (node_id, new Json.Node (Json.NodeType.NULL));
                    return;
                }
            }

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

        message ("!!!handle_response - id=" + id.to_string () + " - " + json_object_to_string (response));

        if (pending_requests.has_key (id)) {
            var promise = pending_requests.get (id);
            pending_requests.unset (id);

            // Сохраняем результат для проснувшегося метода
            responses.set (id, response);

            // Передаем управление обратно в асинхронный метод
            // Используем Idle.add, чтобы вернуться в MainContext (UI поток)
            Idle.add ((owned) promise.callback);
            return;
        }

        if (response.has_member ("method")) {
            var node_result = config.server_response_result (response);
            var node_id = response.get_member ("id");
            send_response_async.begin (node_id, node_result);
        }

        // if (response.has_member ("method")) {
        // string method = response.get_string_member ("method");
        // switch (method) {
        // case "client/registerCapability" : {
        // message ("!!!handle_response - client/registerCapability - " + json_object_to_string (response));
        // var node_id = response.get_member ("id");
        // send_response_async.begin (node_id, new Json.Node (Json.NodeType.NULL));
        // } return;
        // case "workspace/configuration" : {
        // message ("!!!handle_response - workspace/configuration - " + json_object_to_string (response));
        // handle_response_workspace_configuration (response);
        // } return;
        // }
        // }
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
            if (params != null) {
                string uri = params.get_string_member ("uri");
                var json_array = params.get_array_member ("diagnostics");

                // Парсим JSON-массив в список ваших объектов IdeLspDiagnostic
                var diag_list = this.parse_diagnostics (json_array);

                message ("!!!handle_incoming_notification - textDocument/publishDiagnostics: " + uri);

                // Передаем в главный поток для UI
                Idle.add (() => {
                    this.diagnostics_received (uri, diag_list);
                    return Source.REMOVE;
                });
            }
            break;

        case "window/workDoneProgress/create" :
            message ("!!!handle_incoming_notification - window/workDoneProgress/create" + json_object_to_string (root));
            break;

        case "$/progress" :
            message ("!!!handle_incoming_notification - $/progress" + json_object_to_string (root));
            break;

        case "window/logMessage":
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

    private void handle_log_message (Json.Object params) {
        int type = (int) params.get_int_member ("type");
        string message = params.get_string_member ("message");

        Idle.add (() => {
            this.log_message (type, message);
            return Source.REMOVE;
        });
    }

    public async bool start_server_async (string? workspace_root) {
        try {
            // 1. Подготовка аргументов запуска
            string[] argv = { config.command () };
            foreach (var arg in config.args ())argv += arg;

            // 2. Запуск подпроцесса
            var launcher = new SubprocessLauncher (SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDIN_PIPE);
            this.process = launcher.spawnv (argv);

            // 3. Инициализация асинхронных потоков
            this.output_stream = this.process.get_stdin_pipe ();
            this.input_stream = new DataInputStream (this.process.get_stdout_pipe ());

            // 4. Запуск цикла чтения (он будет ждать сообщений в фоне)
            this.run_read_loop.begin ();

            // 5. Фаза INITIALIZE
            // var init_params = build_init_params (workspace_root, initialization_options);
            var init_params = config.initialize_params (workspace_root, null);
            message ("!!!initialize: " + json_object_to_string (init_params.get_object ()));
            var response = yield this.send_request ("initialize", init_params.get_object ());

            message ("!!!initialized-->: " + json_object_to_string (response));

            if (response != null && response.has_member ("result")) {
                var result = response.get_object_member ("result");
                // Извлекаем возможности сервера
                message ("-->parse_capabilities");
                this.parse_capabilities (result);
                message ("<--parse_capabilities");
            }

            // Используем Idle.add, чтобы оповестить подписчиков в главном потоке
            is_initialized = true;
            Idle.add (() => {
                this.initialized_with_capabilities (this.capabilities);
                return Source.REMOVE; // Выполнить один раз
            });

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
        this.capabilities.hover_provider = caps.has_member ("hoverProvider");
        this.capabilities.definition_provider = caps.has_member ("definitionProvider");
    }

    public async void send_notification_async (string method, Json.Object params) throws Error {
        var root = new Json.Object ();
        root.set_string_member ("jsonrpc", "2.0");
        root.set_string_member ("method", method);
        root.set_object_member ("params", params);

        // Вызываем наш атомарный метод записи в поток
        yield this.send_message_async (root);
    }

    private Gee.ArrayList<IdeLspDiagnostic> parse_diagnostics (Json.Array diagnostics_array) {
        var result = new Gee.ArrayList<IdeLspDiagnostic> ();

        foreach (var diag_node in diagnostics_array.get_elements ()) {
            var diag_obj = diag_node.get_object ();
            var d = new IdeLspDiagnostic ();

            // Основные поля
            d.message = diag_obj.get_string_member ("message");
            if (diag_obj.has_member ("severity")) {
                d.severity = (int) diag_obj.get_int_member ("severity");
            }

            // Координаты (Range в LSP содержит start и end объекты)
            var range = diag_obj.get_object_member ("range");
            var start = range.get_object_member ("start");
            var end = range.get_object_member ("end");

            d.start_line = (int) start.get_int_member ("line");
            d.start_column = (int) start.get_int_member ("character"); // character -> start_column
            d.end_line = (int) end.get_int_member ("line");
            d.end_column = (int) end.get_int_member ("character"); // character -> end_column

            result.add (d);
        }

        return result;
    }

    public async void text_document_did_open (string uri, string language_id, int version, string content) throws Error {
        var params = new Json.Object ();

        var doc = new Json.Object ();
        doc.set_string_member ("uri", uri);
        doc.set_string_member ("languageId", language_id);
        doc.set_int_member ("version", version);
        doc.set_string_member ("text", content);

        params.set_object_member ("textDocument", doc);

        message ("!!!text_document_did_open - ");

        // Это уведомление (notification), оно не требует ID и не ждет ответа
        yield this.send_notification_async ("textDocument/didOpen", params);

        debug ("LSP: Sent didOpen for %s", uri);
    }

    public async void text_document_did_change (string uri, int version, string content) throws Error {
        var params = new Json.Object ();

        // 1. Идентификатор документа
        var doc = new Json.Object ();
        doc.set_string_member ("uri", uri);
        doc.set_int_member ("version", version);
        params.set_object_member ("textDocument", doc);

        // 2. Полное содержимое (без поля range)
        var change = new Json.Object ();
        change.set_string_member ("text", content);

        var changes = new Json.Array ();
        changes.add_object_element (change);
        params.set_array_member ("contentChanges", changes);

        yield this.send_notification_async ("textDocument/didChange", params);
    }

    public async void send_did_change (string uri, int version, Gee.ArrayList<PendingChange> changes) throws Error {
        var params = new Json.Object ();

        // 1. Идентификатор документа
        var doc = new Json.Object ();
        doc.set_string_member ("uri", uri);
        doc.set_int_member ("version", version);
        params.set_object_member ("textDocument", doc);

        // 2. Массив инкрементальных изменений
        var json_changes = new Json.Array ();
        foreach (var c in changes) {
            var obj = new Json.Object ();

            // Формируем диапазон (range)
            var range = new Json.Object ();

            var start = new Json.Object ();
            start.set_int_member ("line", c.start_line);
            start.set_int_member ("character", c.start_char);

            var end = new Json.Object ();
            end.set_int_member ("line", c.end_line);
            end.set_int_member ("character", c.end_char);

            range.set_object_member ("start", start);
            range.set_object_member ("end", end);

            obj.set_object_member ("range", range);
            obj.set_string_member ("text", c.text);

            json_changes.add_object_element (obj);
        }
        params.set_array_member ("contentChanges", json_changes);

        yield this.send_notification_async ("textDocument/didChange", params);
    }

    public async void text_document_did_close (string uri) throws Error {
        var params = new Json.Object ();
        var doc = new Json.Object ();
        doc.set_string_member ("uri", uri);
        params.set_object_member ("textDocument", doc);

        yield this.send_notification_async ("textDocument/didClose", params);
    }

    private IdeLspCompletionResult parse_completion_result (Json.Node node) {
        var res = new IdeLspCompletionResult ();
        res.items = new Gee.ArrayList<IdeLspCompletionItem> ();

        Json.Array? items_array = null;

        // Случай 1: Сервер вернул объект CompletionList { isIncomplete, items }
        if (node.get_node_type () == Json.NodeType.OBJECT) {
            var obj = node.get_object ();
            if (obj.has_member ("isIncomplete")) {
                res.is_incomplete = obj.get_boolean_member ("isIncomplete");
            }
            if (obj.has_member ("items")) {
                items_array = obj.get_array_member ("items");
            }
        }
        // Случай 2: Сервер вернул просто массив CompletionItem[]
        else if (node.get_node_type () == Json.NodeType.ARRAY) {
            items_array = node.get_array ();
        }

        if (items_array != null) {
            foreach (var item_node in items_array.get_elements ()) {
                var item_obj = item_node.get_object ();
                var item = new IdeLspCompletionItem ();

                item.label = item_obj.get_string_member ("label");

                // Опциональные поля
                if (item_obj.has_member ("insertText"))
                    item.insert_text = item_obj.get_string_member ("insertText");
                else
                    item.insert_text = item.label;

                if (item_obj.has_member ("detail"))
                    item.detail = item_obj.get_string_member ("detail");

                if (item_obj.has_member ("kind"))
                    item.kind = (int) item_obj.get_int_member ("kind");

                // Обработка документации (может быть строкой или объектом MarkupContent)
                if (item_obj.has_member ("documentation")) {
                    var doc_node = item_obj.get_member ("documentation");
                    if (doc_node.get_node_type () == Json.NodeType.OBJECT)
                        item.documentation = doc_node.get_object ().get_string_member ("value");
                    else
                        item.documentation = doc_node.get_string ();
                }

                res.items.add (item);
            }
        }

        return res;
    }

    public async IdeLspCompletionResult ? request_completion (string uri, int line, int character, string? trigger_char = null, CompletionTriggerKind trigger_kind = CompletionTriggerKind.INVOKED) throws Error {
        var params = new Json.Object ();

        var doc = new Json.Object ();
        doc.set_string_member ("uri", uri);
        params.set_object_member ("textDocument", doc);

        var pos = new Json.Object ();
        pos.set_int_member ("line", line);
        pos.set_int_member ("character", character);
        params.set_object_member ("position", pos);

        var context = new Json.Object ();
        context.set_int_member ("triggerKind", (int) trigger_kind);
        if (trigger_char != null) {
            context.set_string_member ("triggerCharacter", trigger_char);
        }
        params.set_object_member ("context", context);

        var response = yield this.send_request ("textDocument/completion", params);

        if (response == null || !response.has_member ("result"))return null;

        var result_node = response.get_member ("result");
        if (result_node.get_node_type () == Json.NodeType.NULL)return null;

        return parse_completion_result (result_node);
    }

    private string ? parse_hover_result (Json.Node node) {
        if (node.get_node_type () != Json.NodeType.OBJECT)
            return null;

        var result = node.get_object ();

        // Случай 1: содержимое в поле 'contents'
        if (!result.has_member ("contents"))
            return null;

        var contents = result.get_member ("contents");

        // Если это объект (MarkupContent)
        if (contents.get_node_type () == Json.NodeType.OBJECT) {
            var obj = contents.get_object ();
            if (obj.has_member ("value")) {
                return obj.get_string_member ("value");
            }
        }
        // Если это просто строка или массив строк
        else {
            return contents.get_string ();
        }

        return null;
    }

    public async string ? request_hover (string uri, int line, int character) throws Error {
        var params = new Json.Object ();

        var doc = new Json.Object ();
        doc.set_string_member ("uri", uri);
        params.set_object_member ("textDocument", doc);

        var pos = new Json.Object ();
        pos.set_int_member ("line", line);
        pos.set_int_member ("character", character);
        params.set_object_member ("position", pos);

        var response = yield this.send_request ("textDocument/hover", params);

        if (response == null || !response.has_member ("result"))return null;

        return parse_hover_result (response.get_member ("result"));
    }

    public async Gee.ArrayList<IdeLspLocation>? request_definition (string uri, int line, int character) throws Error {
        var params = new Json.Object ();

        var doc = new Json.Object ();
        doc.set_string_member ("uri", uri);
        params.set_object_member ("textDocument", doc);

        var pos = new Json.Object ();
        pos.set_int_member ("line", line);
        pos.set_int_member ("character", character);
        params.set_object_member ("position", pos);

        var response = yield this.send_request ("textDocument/definition", params);

        if (response == null || !response.has_member ("result"))return null;

        var result_node = response.get_member ("result");
        if (result_node.get_node_type () == Json.NodeType.NULL)return null;

        return parse_definition_result (result_node);
    }

    private Gee.ArrayList<IdeLspLocation> parse_definition_result (Json.Node node) {
        var locations = new Gee.ArrayList<IdeLspLocation> ();

        // Случай 1: Одиночный объект Location {}
        if (node.get_node_type () == Json.NodeType.OBJECT) {
            var loc = parse_single_location (node.get_object ());
            if (loc != null)locations.add (loc);
        }
        // Случай 2: Массив объектов Location[]
        else if (node.get_node_type () == Json.NodeType.ARRAY) {
            var array = node.get_array ();
            foreach (var element in array.get_elements ()) {
                var loc = parse_single_location (element.get_object ());
                if (loc != null)locations.add (loc);
            }
        }

        return locations;
    }

    private IdeLspLocation ? parse_single_location (Json.Object obj) {
        var loc = new IdeLspLocation ();
        loc.uri = obj.get_string_member ("uri");

        var range = obj.get_object_member ("range");
        var start = range.get_object_member ("start");
        var end = range.get_object_member ("end");

        loc.start_line = (int) start.get_int_member ("line");
        loc.start_column = (int) start.get_int_member ("character");
        loc.end_line = (int) end.get_int_member ("line");
        loc.end_column = (int) end.get_int_member ("character");

        return loc;
    }
}
