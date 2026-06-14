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

public struct Iide.LspTaskInfo {
    public string server_name;
    public string message;
    public int percentage; // -1 если процентов нет
}

/**
 * Легковесный контейнер для сохранения асинхронного колбэка
 */
private class Iide.LspWriteWaiter : GLib.Object {
    // Сохраняем делегат как owned, чтобы Vala корректно управляла памятью контекста
    public SourceFunc? callback { get; set; }

    public LspWriteWaiter (owned SourceFunc? cb) {
        this.callback = (owned) cb;
    }
}

public class Iide.LspClient : Object {
    private int next_id = 0;
    private Map<int, LspPromise> pending_requests = new HashMap<int, LspPromise> ();
    private Map<int, Json.Object?> responses = new HashMap<int, Json.Object?> ();
    private LspConfig config;

    private DiagnosticsService diagnostics_service;

    // Процесс LSP сервера
    private GLib.Subprocess process;

    // Поток для чтения (стандартный вывод сервера)
    private GLib.DataInputStream input_stream;

    // Поток для записи (стандартный ввод сервера)
    private Gee.ArrayList<LspWriteWaiter> write_waiters = new Gee.ArrayList<LspWriteWaiter> ();
    private OutputStream output_stream;

    private bool is_stopping = false;
    private GLib.Cancellable read_cancellable = new GLib.Cancellable ();

    // Сигнал для передачи диагностики в UI
    public signal void diagnostics_received (string uri, Gee.ArrayList<LspDiagnosticPair?> diagnostics);

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
        this.diagnostics_service = DiagnosticsService.get_instance ();
    }

    public signal void progress_updated (string token, string message, int percentage, bool active);

    public string name () { return config.command[0]; }

    public int get_hash () {
        // Используем адрес указателя на объект как уникальный числовой идентификатор
        return (int) ((void*) this);
    }

    public async Json.Object? send_request (string method, Json.Object params, Cancellable ? cancellable = null) throws Error {
        int id = next_id--;

        var root = new Json.Object ();
        root.set_string_member ("jsonrpc", "2.0");
        root.set_int_member ("id", id);
        root.set_string_member ("method", method);
        root.set_object_member ("params", params);

        // Регистрируем обещание
        var promise = new LspPromise (send_request.callback);
        pending_requests.set (id, promise);

        // Обработка отмены: если произойдет отмена, пока мы спим, нужно "разбудить" метод
        ulong handler_id = 0;
        if (cancellable != null) {
            handler_id = cancellable.connect (() => {
                // Если мы всё еще ждем этот запрос, выбиваем его из очереди
                if (pending_requests.has_key (id)) {
                    pending_requests.unset (id);
                    // Пробуждаем метод. Idle.add важен для возврата в UI поток.
                    Idle.add ((owned) promise.callback);
                }
            });
        }

        try {
            // Передаем cancellable в процесс записи
            yield this.send_message_async (root, cancellable);

            // Засыпаем до получения ответа ИЛИ до вызова колбэка через сигнал отмены
            yield;

            // После пробуждения проверяем, не была ли это отмена
            if (cancellable != null && cancellable.is_cancelled ()) {
                throw new IOError.CANCELLED ("Запрос %s (id: %d) был отменен".printf (method, id));
            }

            // Если не отмена, забираем результат
            var response = responses.get (id);
            responses.unset (id);
            return response;
        } finally {
            // Обязательно отключаем обработчик, чтобы не плодить утечки памяти
            if (handler_id > 0) {
                cancellable.disconnect (handler_id);
            }
        }
    }

    private async void send_message_async (Json.Object node, Cancellable? cancellable = null) throws Error {
        var generator = new Json.Generator ();
        var root_node = new Json.Node (Json.NodeType.OBJECT);
        root_node.set_object (node);
        generator.set_root (root_node);

        string body = generator.to_data (null);
        string message = "Content-Length: %d\r\n\r\n%s".printf ((int) body.length, body);

        // ===================================================================
        // Если в очереди КТО-ТО уже стоит, значит, поток занят.
        // Мы добавляем себя в хвост очереди и засыпаем на месте.
        // ===================================================================
        if (this.write_waiters.size > 0) {
            var waiter = new LspWriteWaiter (send_message_async.callback);
            this.write_waiters.add (waiter);
            yield; // Спим, пока нас не разбудит предыдущий метод
        } else {
            // Если очередь была пуста, мы первые! 
            // Добавляем пустышку-маркер в очередь, чтобы ВСЕ последующие 
            // вызовы знали, что труба сейчас занята и ложились спать.
            var marker = new LspWriteWaiter (null);
            this.write_waiters.add (marker);
        }

        try {
            if (cancellable != null && cancellable.is_cancelled ()) {
                throw new IOError.CANCELLED ("Отмена операции отправки сообщения");
            }

            // Физически проталкиваем байты в сеть [INDEX]
            yield output_stream.write_all_async (message.data, Priority.DEFAULT, cancellable, null);
            yield output_stream.flush_async (Priority.DEFAULT, cancellable);

        } finally {
            // Мы закончили писать байты. Удаляем СЕБЯ (самый первый элемент) из головы очереди!
            if (this.write_waiters.size > 0) {
                this.write_waiters.remove_at (0);
            }
            
            // Если за время нашей записи сзади пристроились новые асинхронные запросы,
            // мы берем тот, который стоит следующим в очереди, и нежно его будим [INDEX]
            if (this.write_waiters.size > 0) {
                var next_waiter = this.write_waiters.get (0);
                if (next_waiter.callback != null) {
                    Idle.add (next_waiter.callback);
                }
            }
        }
    }

    private async void run_read_loop () {
        try {
            while (true) {
                // 1. Читаем заголовок Content-Length
                string? line = yield input_stream.read_line_async (Priority.DEFAULT, this.read_cancellable);

                if (line == null)break; // Поток закрыт

                if (line.has_prefix ("Content-Length: ")) {
                    int length = int.parse (line.substring (16).strip ());

                    // 2. Пропускаем все остальные заголовки до пустой строки (\r\n\r\n)
                    while (line != "" && line != null) {
                        line = yield input_stream.read_line_async (Priority.DEFAULT, this.read_cancellable);

                        if (line != null)line = line.strip ();
                    }

                    // 3. Читаем тело JSON строго по длине
                    uint8[] buffer = new uint8[length + 1];
                    size_t bytes_read;
                    yield input_stream.read_all_async (buffer[0 : length], Priority.DEFAULT, this.read_cancellable, out bytes_read);

                    buffer[length] = '\0'; // Гарантируем конец строки для парсера

                    // 4. Обрабатываем полученный пакет
                    this.handle_payload ((string) buffer);
                }
            }
        } catch (Error e) {
            // Когда мы отменим операцию при закрытии, метод проснется здесь! [INDEX]
            if (e is IOError.CANCELLED) {
                LoggerService.get_instance ().debug ("LSP", "LSP Read Loop successfully cancelled and stopped.");
            } else {
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

        yield this.send_message_async (root);
    }

    private void handle_payload (string payload) {
        try {
            var parser = new Json.Parser ();
            parser.load_from_data (payload);
            var root = parser.get_root ().get_object ();

            if (root.has_member ("method")) {
                string method = root.get_string_member ("method");
                if (method == "window/workDoneProgress/create" && root.has_member ("id")) {
                    // Мы просто подтверждаем, что готовы принимать прогресс с этим токеном
                    var node_id = root.get_member ("id");
                    send_response_async.begin (node_id, new Json.Node (Json.NodeType.NULL));
                    return;
                }
                if (method == "workspace/diagnostic/refresh" && root.has_member ("id")) {
                    // Мы просто подтверждаем, что готовы принимать прогресс с этим токеном
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
            var node_result = config.handle_workspace_configuration (response);
            var node_id = response.get_member ("id");
            send_response_async.begin (node_id, node_result);
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
            if (params != null) {
                string uri = params.get_string_member ("uri");
                var json_array = params.get_array_member ("diagnostics");

                // Парсим JSON-массив в список ваших объектов IdeLspDiagnostic
                var diag_list = this.parse_diagnostics (json_array);

                // Передаем в главный поток для UI
                Idle.add (() => {
                    // Передаем данные в глобальную модель
                    diagnostics_service.update_diagnostics (this.get_hash (), uri, diag_list);

                    this.diagnostics_received (uri, diag_list);
                    return Source.REMOVE;
                });
            }
            break;

        case "window/workDoneProgress/create" :
            message ("!!!handle_incoming_notification - window/workDoneProgress/create" + json_object_to_string (root));
            break;

        case "$/progress" :
            // message ("!!!handle_incoming_notification - $/progress" + json_object_to_string (root));
            if (params != null) {
                // Token может быть строкой или числом, Tree-sitter и LSP это допускают
                string token = "";
                var token_node = params.get_member ("token");
                if (token_node.get_node_type () == Json.NodeType.VALUE) {
                    token = token_node.get_string ();
                } else {
                    token = token_node.get_int ().to_string ();
                }

                var value = params.get_object_member ("value");
                string kind = value.get_string_member ("kind");

                // Определяем состояние
                bool active = (kind != "end");
                if (kind == "end") {
                    var sparams = new Json.Object ();
                    sparams.set_string_member ("query", "");

                    send_request.begin ("workspace/symbol", sparams);
                }

                // Извлекаем сообщение (у BasedPyright оно часто в 'message')
                string msg = "";
                if (value.has_member ("title")) {
                    msg = value.get_string_member ("title");
                }
                if (value.has_member ("message")) {
                    string details = value.get_string_member ("message");
                    msg = (msg != "") ? @"$msg: $details" : details;
                }

                // Извлекаем проценты (если есть)
                int perc = value.has_member ("percentage") ? (int) value.get_int_member ("percentage") : -1;

                // Передаем в главный поток для обновления UI
                Idle.add (() => {
                    this.progress_updated (token, msg, perc, active);
                    return Source.REMOVE;
                });
            }
            break;
        case "window/logMessage" :
            if (params != null)handle_log_message (params);
            break;

        case "window/showMessage" :
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
            // 2. Запуск подпроцесса
            var launcher = new SubprocessLauncher (SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDIN_PIPE);
            launcher.set_cwd (workspace_root.replace ("file://", ""));
            this.process = launcher.spawnv (config.command);

            // 3. Инициализация асинхронных потоков
            this.output_stream = this.process.get_stdin_pipe ();
            this.input_stream = new DataInputStream (this.process.get_stdout_pipe ());

            // 4. Запуск цикла чтения (он будет ждать сообщений в фоне)
            this.run_read_loop.begin ();

            // 5. Фаза INITIALIZE
            var init_params = config.initialize_params (workspace_root);
            var response = yield this.send_request ("initialize", init_params.get_object ());

            if (response != null && response.has_member ("result")) {
                var result = response.get_object_member ("result");
                // Извлекаем возможности сервера
                this.parse_capabilities (result);
            }

            // Используем Idle.add, чтобы оповестить подписчиков в главном потоке
            is_initialized = true;
            Idle.add (() => {
                this.initialized_with_capabilities (this.capabilities);
                LspService.get_instance ().register_client (this);
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

    private Gee.ArrayList<LspDiagnosticPair?> parse_diagnostics (Json.Array diagnostics_array) {
        var result = new Gee.ArrayList<LspDiagnosticPair?> ();

        foreach (var diag_node in diagnostics_array.get_elements ()) {
            var diag_obj = diag_node.get_object ();
            var d = new LspDiagnostic ();

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

            // ===================================================================
            // СВЯЗЫВАНИЕ: Создаем глубокую копию оригинального JSON-объекта, 
            // чтобы он гарантированно остался в памяти после очистки RPC-ответа [INDEX]
            // ===================================================================
            var node_copy = new Json.Node (Json.NodeType.OBJECT);
            node_copy.set_object (diag_obj);
            var cloned_json = node_copy.copy ().get_object ();

            // Упаковываем распарсенный объект и его сырой JSON в структуру [INDEX]
            var pair = Iide.LspDiagnosticPair (d, cloned_json);
            result.add (pair);
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
            start.set_int_member ("character", c.start_utf16_char);

            var end = new Json.Object ();
            end.set_int_member ("line", c.end_line);
            end.set_int_member ("character", c.end_utf16_char);

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

    private LspCompletionResult parse_completion_result (Json.Node node) {
        var res = new LspCompletionResult ();
        res.items = new Gee.ArrayList<LspCompletionItem> ();

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
                var item = new LspCompletionItem ();

                item.label = item_obj.get_string_member ("label");

                // Опциональные поля
                if (item_obj.has_member ("insertText"))
                    item.insert_text = item_obj.get_string_member ("insertText");
                else
                    item.insert_text = item.label;

                if (item_obj.has_member ("detail"))
                    item.detail = item_obj.get_string_member ("detail");

                if (item_obj.has_member ("kind"))
                    item.kind = (LspCompletionKind) item_obj.get_int_member ("kind");

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

    public async LspCompletionResult ? request_completion (string uri, int line, int character, string? trigger_char = null, CompletionTriggerKind trigger_kind = CompletionTriggerKind.INVOKED) throws Error {
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

    public async Gee.List<DocumentLspSymbol>? document_symbols (string uri, Cancellable ? cancellable = null) throws Error {
        var params = new Json.Object ();

        var doc = new Json.Object ();
        doc.set_string_member ("uri", uri);
        params.set_object_member ("textDocument", doc);

        var response = yield this.send_request ("textDocument/documentSymbol", params, cancellable);

        if (response == null || !response.has_member ("result"))
            return null;

        var node = new Json.Node(Json.NodeType.OBJECT);
        node.set_object(response);
        LoggerService.get_instance ().info("DS", Json.to_string (node, true));


        var result = parse_document_lsp_symbols (response.get_member ("result"));
        
        return result;
    }

    public async Gee.List<WorkspaceLspSymbol>? workspace_symbols (string query, Cancellable ? cancellable = null) throws Error {
        var params = new Json.Object ();
        params.set_string_member ("query", query);

        var response = yield this.send_request ("workspace/symbol", params, cancellable);

        if (response == null || !response.has_member ("result"))
            return null;

        return parse_workspace_lsp_symbols (response.get_member ("result"));
    }

    public Gee.List<WorkspaceLspSymbol> parse_workspace_lsp_symbols (Json.Node root_node) {
        var result = new Gee.ArrayList<WorkspaceLspSymbol> ();

        // Проверяем, что корень — это массив
        if (root_node.get_node_type () != Json.NodeType.ARRAY)return result;

        var array = root_node.get_array ();

        foreach (var element in array.get_elements ()) {
            var obj = element.get_object ();
            var symbol = new WorkspaceLspSymbol ();

            symbol.name = obj.get_string_member ("name");
            symbol.kind = (SymbolKind) obj.get_int_member ("kind");

            if (obj.has_member ("containerName")) {
                symbol.container_name = obj.get_string_member ("containerName");
            }

            // Парсим Location (URI и Range)
            var location = obj.get_object_member ("location");
            symbol.uri = location.get_string_member ("uri");

            var range = location.get_object_member ("range");
            var start = range.get_object_member ("start");

            symbol.start_line = (int) start.get_int_member ("line");
            symbol.start_char = (int) start.get_int_member ("character");

            result.add (symbol);
        }

        return result;
    }

    public async Gee.ArrayList<LspLocation>? request_definition (string uri, int line, int character) throws Error {
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

    private Gee.ArrayList<LspLocation> parse_definition_result (Json.Node node) {
        var locations = new Gee.ArrayList<LspLocation> ();

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

    private LspLocation ? parse_single_location (Json.Object obj) {
        var loc = new LspLocation ();
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

    public Gee.List<Iide.DocumentLspSymbol> parse_document_lsp_symbols (Json.Node root_node) {
        var result = new Gee.ArrayList<Iide.DocumentLspSymbol> ();

        // Проверяем тип узла (должен быть массив)
        if (root_node.get_node_type () != Json.NodeType.ARRAY)return result;

        var array = root_node.get_array ();
        foreach (var element in array.get_elements ()) {
            if (element.get_node_type () != Json.NodeType.OBJECT)continue;

            var symbol = parse_single_document_lsp_symbol (element.get_object (), null);
            result.add (symbol);
        }

        return result;
    }

    private Iide.DocumentLspSymbol? parse_single_document_lsp_symbol (Json.Object obj, string? parent_name) {
        // 1. Создаем объект и ПРОВЕРЯЕМ, что он создался
        var symbol = new Iide.DocumentLspSymbol ();
        if (symbol == null) return null;

        // 2. Используем локальные переменные для безопасности
        string name = "Unknown";
        if (obj.has_member ("name")) {
            name = obj.get_string_member ("name");
        }
        symbol.name = name; // Здесь может быть триггер notify

        if (obj.has_member ("kind")) {
            symbol.kind = (SymbolKind) obj.get_int_member ("kind");
        }

        symbol.container_name = parent_name;

        // 3. Координаты (выделяем в блок для безопасности)
        Json.Object? range_obj = null;
        if (obj.has_member ("selectionRange")) range_obj = obj.get_object_member ("selectionRange");
        else if (obj.has_member ("range")) range_obj = obj.get_object_member ("range");

        if (range_obj != null) {
            if (range_obj.has_member ("start")) {
                var start = range_obj.get_object_member ("start");
                symbol.start_line = (int) start.get_int_member ("line");
                symbol.start_char = (int) start.get_int_member ("character");
            }
        }

        // 4. РЕКУРСИЯ (Самое опасное место)
        if (obj.has_member ("children")) {
            var children_node = obj.get_member ("children");
            if (children_node != null && !children_node.is_null() && children_node.get_node_type() == Json.NodeType.ARRAY) {
                var children_array = children_node.get_array();
                foreach (var child_node in children_array.get_elements()) {
                    // ПРОВЕРЯЕМ, ЧТО ЭТО ОБЪЕКТ ПЕРЕД ТЕМ КАК ВЫЗВАТЬ get_object()
                    if (child_node != null && child_node.get_node_type() == Json.NodeType.OBJECT) {
                        var child_symbol = parse_single_document_lsp_symbol (child_node.get_object(), symbol.name);
                        if (child_symbol != null) {
                            symbol.children.add (child_symbol);
                        }
                    }
                }
            }
        }

        return symbol;
    }

    /**
     * Запрос доступных Code Actions (быстрых исправлений) для указанного диапазона и списка диагностик
     * @param diagnostics_json_array Массив Json.Array, содержащий сырые объекты диагностик от сервера для этой строки
     */
    public async LspCodeActionResult? request_code_actions (string uri, int start_line, int start_char, int end_line, int end_char, Json.Array diagnostics_json_array) throws Error {
        var params = new Json.Object ();

        // 1. Указываем документ [INDEX]
        var doc = new Json.Object ();
        doc.set_string_member ("uri", uri);
        params.set_object_member ("textDocument", doc);

        // 2. Указываем диапазон (обычно текущая строка или выделение) [INDEX]
        var range = new Json.Object ();
        var start_pos = new Json.Object ();
        start_pos.set_int_member ("line", start_line);
        start_pos.set_int_member ("character", start_char);
        range.set_object_member ("start", start_pos);

        var end_pos = new Json.Object ();
        end_pos.set_int_member ("line", end_line);
        end_pos.set_int_member ("character", end_char);
        range.set_object_member ("end", end_pos);
        params.set_object_member ("range", range);

        // 3. Формируем контекст с диагностиками [INDEX]
        var context = new Json.Object ();
        // Передаем массив диагностик, который мы получили от publishDiagnostics для этой строки [INDEX]
        context.set_array_member ("diagnostics", diagnostics_json_array);
        params.set_object_member ("context", context);

        // 4. Отправляем запрос серверу [INDEX]
        var response = yield this.send_request ("textDocument/codeAction", params);

        if (response == null || !response.has_member ("result")) return null;

        var result_node = response.get_member ("result");
        if (result_node.get_node_type () == Json.NodeType.NULL) return null;

        return parse_code_action_result (result_node);
    }

    /**
     * Парсер ответа CodeAction[] от LSP-сервера
     */
    private LspCodeActionResult parse_code_action_result (Json.Node node) {
        var res = new LspCodeActionResult ();
        res.actions = new Gee.ArrayList<LspCodeActionItem> ();

        if (node.get_node_type () != Json.NodeType.ARRAY) return res;
        var actions_array = node.get_array ();

        foreach (var action_node in actions_array.get_elements ()) {
            if (action_node.get_node_type () != Json.NodeType.OBJECT) continue;
            
            var action_obj = action_node.get_object ();
            var item = new LspCodeActionItem ();

            // Читаем базовые поля [INDEX]
            item.title = action_obj.get_string_member ("title");
            if (action_obj.has_member ("kind")) {
                item.kind = action_obj.get_string_member ("kind");
            }

            // Читаем структуру изменений WorkspaceEdit (edit.changes) [INDEX]
            if (action_obj.has_member ("edit")) {
                var edit_obj = action_obj.get_object_member ("edit");
                
                if (edit_obj.has_member ("changes")) {
                    var changes_obj = edit_obj.get_object_member ("changes");

                    // Итерируем по всем URI файлов, для которых сервер предлагает правки [INDEX]
                    foreach (string file_uri in changes_obj.get_members ()) {
                        var edits_array = changes_obj.get_array_member (file_uri);
                        var edits_list = new Gee.ArrayList<LspTextEdit> ();

                        foreach (var edit_node in edits_array.get_elements ()) {
                            var edit_data = edit_node.get_object ();
                            var text_edit = new LspTextEdit ();
                            
                            text_edit.new_text = edit_data.get_string_member ("newText");

                            var r = edit_data.get_object_member ("range");
                            var start = r.get_object_member ("start");
                            var end = r.get_object_member ("end");

                            text_edit.start_line = (int) start.get_int_member ("line");
                            text_edit.start_char = (int) start.get_int_member ("character");
                            text_edit.end_line = (int) end.get_int_member ("line");
                            text_edit.end_char = (int) end.get_int_member ("character");

                            edits_list.add (text_edit);
                        }

                        item.changes.set (file_uri, edits_list);
                    }
                }
            }

            res.actions.add (item);
        }

        return res;
    }

    /**
     * ДВУХФАЗНОЕ ЗАВЕРШЕНИЕ РАБОТЫ LSP-СЕРВЕРА (Версия для подготовки к рефакторингу)
     */
    public async void shutdown_and_exit_async () {
        // Если закрытие уже запущено, выходим, чтобы не дублировать запросы
        if (this.is_stopping) {
            return;
        }
        this.is_stopping = true;

        LoggerService.get_instance ().info ("LSP", @"Initiating clean shutdown for server...");

        try {
            // ФАЗА 1: Отправляем запрос 'shutdown' и асинхронно ждем подтверждения от сервера [INDEX]
            var empty_params = new Json.Object ();
            var response = yield this.send_request ("shutdown", empty_params);
            
            if (response != null) {
                LoggerService.get_instance ().debug ("LSP", "Server acknowledged shutdown.");
            }
        } catch (GLib.Error e) {
            // Если сервер завис — логируем, но принудительно продолжаем выход
            LoggerService.get_instance ().warning ("LSP", @"Shutdown request failed: $(e.message). Forcing exit...");
        }

        try {
            // ФАЗА 2: Отправляем обязательное уведомление 'exit' (fire-and-forget) [INDEX]
            var empty_params = new Json.Object ();
            yield this.send_notification_async ("exit", empty_params);
            LoggerService.get_instance ().info ("LSP", "Sent 'exit' notification to server.");
        } catch (GLib.Error e) {
            LoggerService.get_instance ().error ("LSP", @"Failed to send 'exit' notification: $(e.message)");
        }

        // Шаг 3: Закрываем низкоуровневые асинхронные потоки ввода-вывода
        yield this.close_transport_streams_async ();
    }

    /**
     * Вспомогательный метод закрытия системных потоков ввода-вывода
     */
    /**
     * Асинхронное закрытие системных потоков ввода-вывода
     */
    private async void close_transport_streams_async () {
        // 1. Принудительно отменяем висящие операции чтения в run_read_loop
        this.read_cancellable.cancel ();

        try {
            // 2. Используем close_async вместо close. 
            // Он атомарно дождется, пока флаг pending сбросится, и закроет поток без ошибок
            if (this.output_stream != null && !this.output_stream.is_closed ()) {
                yield this.output_stream.close_async (Priority.DEFAULT, null);
            }
            if (this.input_stream != null && !this.input_stream.is_closed ()) {
                yield this.input_stream.close_async (Priority.DEFAULT, null);
            }
            LoggerService.get_instance ().debug ("LSP", "IO streams closed cleanly.");
        } catch (GLib.Error e) {
            LoggerService.get_instance ().error ("LSP", @"Error closing IO streams: $(e.message)");
        }
        
        this.is_stopping = false;
    }
}