using GLib;
using Gee;

public class Iide.LspPromise : Object {
    public SourceFunc callback;
    // Можно добавить время создания для контроля таймаутов
    public int64 creation_time;
    // Идентификатор таймаута запроса (0 — таймаут не взведён)
    public uint timeout_id = 0;

    public LspPromise (owned SourceFunc cb) {
        this.callback = (owned) cb;
        this.creation_time = get_monotonic_time ();
    }
}

public enum Iide.LspClientStatus {
    STOPPED,
    STARTING,
    INITIALIZING,
    READY,
    FAILED,
    ABORTED
}

public enum Iide.TextDocumentSyncKind {
    NONE = 0,
    FULL = 1,
    INCREMENTAL = 2
}

public enum Iide.LspDiagnosticMode {
    NONE,
    PUSH,   // push-модель (pyright) - присылает ответ в нотификации после didOpen/didChange
    PULL    // pull-модель (ruff) - присылает ответ на запрос textDocument/diagnostic
}

public class Iide.ServerCapabilities : Object {
    public LspDiagnosticMode diagnostics_provider = LspDiagnosticMode.NONE;
    public TextDocumentSyncKind sync_kind = TextDocumentSyncKind.FULL;
    public bool completion_provider = false;
    public HashSet<string> completion_triggers = new HashSet<string> ();
    public bool definition_provider = false;
    public bool hover_provider = false;
    public bool code_actions_provider = false;
    public bool formatting_provider = false;

    // To features...
    public bool references_provider = false;
    public bool rename_provider = false;

    // Workspace file operations (workspace/willRenameFiles, workspace/didRenameFiles)
    public bool will_rename_files_provider = false;
    public bool did_rename_files_provider = false;
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
    public class PendingOpen {
        public string uri;
        public string language_id;
        public string content;
        public string? workspace_root;
        public SourceView view;

        public LspFeatures features { get; private set; }

        public PendingOpen (string uri, string language_id, string content, string? workspace_root, SourceView view) {
            this.uri = uri;
            this.language_id = language_id;
            this.content = content;
            this.workspace_root = workspace_root;
            this.view = view;
        }
    }

    private weak WindowSession session;
    private weak LoggerService logger;

    // Сильная ссылка на текущий временный низкоуровневый процесс ОС
    private Iide.RpcProcess? current_process = null;

    // Текущий статус клиента в конечном автомате
    private LspClientStatus _status = LspClientStatus.STOPPED;
    public LspClientStatus status { 
        get {
            return _status;
        }
        set {
            if (_status != value) {
                if (value == LspClientStatus.READY) {
                    _status = value;
                    Idle.add (() => {
                        this.state_ready_changed (true);
                        return Source.REMOVE;
                    });
                } else {
                    if (_status == LspClientStatus.READY) {
                        _status = value;
                        Idle.add (() => {
                            this.state_ready_changed (false);
                            return Source.REMOVE;
                        });
                    }
                    _status = value;
                }
            }
        }
    }

    private int next_id = 1;
    private Map<int, LspPromise> pending_requests = new HashMap<int, LspPromise> ();
    private Map<int, Json.Object?> responses = new HashMap<int, Json.Object?> ();
    private LspConfig config;
    public string language_id { get; private set; }

    // Таймаут ожидания ответа на запрос в миллисекундах (0 — отключён)
    public uint request_timeout_ms { get; set; default = 15000; }

    // Множество URI документов, открытых на этом сервере (для pull-диагностики)
    private Gee.HashSet<string> open_documents = new Gee.HashSet<string> ();

    private DiagnosticsService diagnostics_service;

    private bool is_stopping = false;
    
    // Свойство возможностей сервера
    public ServerCapabilities capabilities { get; set; }
    public LspFeatures features { get; construct set; }

    // Сигнал для передачи диагностики в UI
    public signal void diagnostics_received (string server_name, string uri, Gee.ArrayList<LspDiagnosticPair?> diagnostics);
    // Сигнал о падении сервера
    public signal void crashed ();
    // Сигнал для логирования сообщений от сервера
    public signal void log_message (int type, string message);
    public signal void stderr_log_received (string log_line);

    public signal void state_ready_changed (bool is_ready);


    // Сигнал, сообщающий, что возможности сервера получены и распарсены
    public signal void initialized_with_capabilities (ServerCapabilities caps);
    
    // Прогресс индексации проекта
    public signal void progress_updated (string token, string message, int percentage, bool active);

    public LspClient (WindowSession session, string language_id, LspConfig config, LspFeatures features) {
        this.session = session;
        this.logger = session.logger_service;
        this.capabilities = new ServerCapabilities ();
        this.config = config;
        this.features = features;
        this.language_id = language_id;
        this.diagnostics_service = session.diagnostics_service;
    }
    
    public string name () { return config.command[0]; }

    /**
     * СТEРИЛЬНЫЙ ЗАПУСК СEРВEРА
     */
    public async bool start_server_async (string? workspace_root) {
        if (this.status != LspClientStatus.STOPPED && 
            this.status != LspClientStatus.FAILED) {
            return false;
        }

        this.status = LspClientStatus.STARTING;
        this.is_stopping = false;

        // 1. Порождаем абсолютно чистый, изолированный объект процесса ОС!
                this.current_process = new Iide.RpcProcess (this.session);

        // 2. Связываем низкоуровневые сигналы с методами нашего монолита
        this.current_process.message_received.connect (this.handle_payload);
        
        // Направляем лог-сигналы в локальный метод вставки строк
        this.current_process.stderr_received.connect ((line) => {
            this.stderr_log_received (line); // Пробрасываем сигнал для UI строки
        });

        this.current_process.unexpected_crash.connect (() => {
            this.status = LspClientStatus.FAILED;
            this.crashed (); // Сигнал краха для LspService и UI строки
        });

        // 3. Запускаем физический спавн в ОС
        bool spawned = yield this.current_process.init_channel (
            this.config.command,
            workspace_root
        );
        if (!spawned) {
            this.status = LspClientStatus.FAILED;
            this.current_process = null;
            return false;
        }

        this.status = LspClientStatus.INITIALIZING;
        logger.info ("LSP", "Server '%s' process spawned. Handshaking 'initialize'...".printf (this.name ()));

        // 4. Прогоняем фазу initialize через стерильную трубу
        try {
            var init_params = this.config.initialize_params (workspace_root);
            
            // Шлем запрос через свежий процесс
            var response = yield this.send_request ("initialize", init_params.get_object ());

            if (response != null && response.has_member ("result")) {
                var result = response.get_object_member ("result");
                this.parse_capabilities (result);
            }

            Idle.add (() => {
                this.initialized_with_capabilities (this.capabilities);
                this.session.lsp_service.register_monitored_client (this);
                return Source.REMOVE; // Выполнить один раз
            });

            yield this.send_notification_async ("initialized", new Json.Object ());
            
            // Смена статуса ДО опустошения очереди, чтобыdidOpen проскочил напрямую
            this.status = LspClientStatus.READY;
            logger.info ("LSP", "Server '%s' started and initialized successfully.".printf (this.name ()));

            return true;
        } catch (GLib.Error e) {
            this.status = LspClientStatus.FAILED;
            this.logger.error ("LSP", "Server '%s' failed to initialize: %s".printf (this.name (), e.message));
            if (this.current_process != null) {
                yield this.current_process.terminate_async ();
                this.current_process = null;
            }
            return false;
        }
    }

    /////////////////////////////////////////////////////////////
    // Send helpers

    public async Json.Object? send_request (string method, Json.Object? params, Cancellable ? cancellable = null) throws Error {
        if (this.current_process == null)
            return null;

        int id = next_id++;

        var root = new Json.Object ();
        root.set_string_member ("jsonrpc", "2.0");
        root.set_int_member ("id", id);
        root.set_string_member ("method", method);
        if (params != null)
            root.set_object_member ("params", params);

        // Регистрируем обещание
        var promise = new LspPromise (send_request.callback);
        pending_requests.set (id, promise);

        // Таймаут: если сервер не ответил — будим запрос с error-ответом
        if (this.request_timeout_ms > 0) {
            promise.timeout_id = Timeout.add (this.request_timeout_ms, () => {
                if (pending_requests.has_key (id)) {
                    pending_requests.unset (id);
                    var err_obj = new Json.Object ();
                    var err_details = new Json.Object ();
                    err_details.set_int_member ("code", -32801);
                    err_details.set_string_member ("message", "Request '%s' (id: %d) timed out".printf (method, id));
                    err_obj.set_object_member ("error", err_details);
                    responses.set (id, err_obj);
                    // Пробуждаем метод. Idle.add важен для возврата в UI поток.
                    Idle.add ((owned) promise.callback);
                }
                return Source.REMOVE;
            });
        }

        // Обработка отмены: если произойдет отмена, пока мы спим, нужно "разбудить" метод
        ulong handler_id = 0;
        if (cancellable != null) {
            handler_id = cancellable.connect (() => {
                // Если мы всё еще ждем этот запрос, выбиваем его из очереди
                if (pending_requests.has_key (id)) {
                    pending_requests.unset (id);
                    this.cancel_request_timeout (promise);
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

            // Поверхность ошибок LSP: error-ответ (или таймаут) превращаем в исключение
            if (response != null && response.has_member ("error")) {
                string msg = "LSP error";
                int code = 0;
                var err_obj = response.get_object_member ("error");
                if (err_obj.has_member ("message"))
                    msg = err_obj.get_string_member ("message");
                if (err_obj.has_member ("code"))
                    code = (int) err_obj.get_int_member ("code");
                throw new IOError.FAILED ("%s (id: %d) failed with LSP error %d: %s".printf (method, id, code, msg));
            }

            return response;
        } finally {
            // Обязательно отключаем обработчик, чтобы не плодить утечки памяти
            if (handler_id > 0) {
                cancellable.disconnect (handler_id);
            }
            // Запрос мог завершиться ошибкой отправки (не дождавшись ответа) — чистим остатки
            if (pending_requests.has_key (id)) {
                pending_requests.unset (id);
            }
            this.cancel_request_timeout (promise);
        }
    }

    private void cancel_request_timeout (LspPromise promise) {
        if (promise.timeout_id > 0) {
            Source.remove (promise.timeout_id);
            promise.timeout_id = 0;
        }
    }

    private async void send_message_async (Json.Object node, Cancellable? cancellable = null) throws Error {
        if (this.current_process == null)
            return;
    
        var generator = new Json.Generator ();
        var root_node = new Json.Node (Json.NodeType.OBJECT);
        root_node.set_object (node);
        generator.set_root (root_node);
        string body = generator.to_data (null);

        yield this.current_process.write_message_async (body);
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
    
    public async void send_notification_async (string method, Json.Object? params) throws Error {
        var root = new Json.Object ();
        root.set_string_member ("jsonrpc", "2.0");
        root.set_string_member ("method", method);
        if (params != null)
            root.set_object_member ("params", params);

        // Вызываем наш атомарный метод записи в поток
        yield this.send_message_async (root);
    }

    /////////////////////////////////////////////////////////////
    // Receive helpers
    
    /**
     * Приемщик сырых JSON пакетов от LspProcess.message_received
     *
     * Строгий трёхпутевой диспетчер по правилам JSON-RPC:
     *  - есть id и method  → запрос от сервера (обязаны ответить);
     *  - есть id, нет method → ответ на наш запрос;
     *  - есть method, нет id → уведомление.
     */
    private void handle_payload (string payload) {
        try {
            var parser = new Json.Parser ();
            parser.load_from_data (payload);
            var root = parser.get_root ().get_object ();

            bool has_id = root.has_member ("id");
            bool has_method = root.has_member ("method");

            if (has_id && has_method) {
                this.handle_server_request (root);
            } else if (has_id) {
                this.handle_response (root);
            } else if (has_method) {
                this.handle_incoming_notification (root);
            } else {
                this.logger.warning ("LSP", "Invalid JSON-RPC message (no id/method): %s".printf (payload));
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
            promise.callback ();
            return;
        }

        this.logger.debug ("LSP", "Ignoring response for unknown/cancelled request id %d".printf (id));
    }

    /**
     * Обработчик запросов от сервера (id + method).
     * По JSON-RPC клиент обязан ответить на каждый запрос, даже неизвестный
     * (ответом null), иначе сервер повиснет на ожидании.
     */
    private void handle_server_request (Json.Object root) {
        string method = root.has_member ("method") ? root.get_string_member ("method") : "";
        var node_id = root.get_member ("id");

        switch (method) {
        case "window/workDoneProgress/create" :
            // Подтверждаем, что готовы принимать прогресс с этим токеном
            this.send_response_async.begin (node_id, new Json.Node (Json.NodeType.NULL));
            break;

        case "workspace/configuration" :
            // Динамический ответ настройками секций из конфигурации сервера
            var node_result = this.config.handle_workspace_configuration (root);
            this.send_response_async.begin (node_id, node_result);
            break;

        case "workspace/diagnostic/refresh" :
            // Подтверждаем и перезапрашиваем pull-диагностику для открытых документов
            this.send_response_async.begin (node_id, new Json.Node (Json.NodeType.NULL));
            this.request_diagnostic_refresh ();
            break;

        case "workspace/workspaceFolders" :
            var folders = new Json.Array ();
            if (this.session != null && this.session.current_project_root != null) {
                var folder = new Json.Object ();
                folder.set_string_member ("uri", this.session.current_project_root.get_uri ());
                folder.set_string_member ("name", this.session.current_project_root.get_basename ());
                folders.add_object_element (folder);
            }
            var folders_node = new Json.Node (Json.NodeType.ARRAY);
            folders_node.set_array (folders);
            this.send_response_async.begin (node_id, folders_node);
            break;

        case "client/registerCapability" :
            this.logger.info ("LSP", "Server '%s' registered dynamic capabilities: %s".printf (this.name (), json_object_to_string (root)));
            this.send_response_async.begin (node_id, new Json.Node (Json.NodeType.NULL));
            break;

        case "workspace/applyEdit" :
            this.handle_workspace_apply_edit.begin (node_id, root);
            break;

        default:
            this.logger.debug ("LSP", "Unhandled server request '%s' from '%s'; acknowledging with null.".printf (method, this.name ()));
            this.send_response_async.begin (node_id, new Json.Node (Json.NodeType.NULL));
            break;
        }
    }

    /**
     * Применение правок из серверного запроса workspace/applyEdit (LSP 3.13+).
     * Правки накатываются через DocumentManager (в открытых документах или с
     * открытием недостающих), после чего серверу возвращается { "applied": true }.
     */
    private async void handle_workspace_apply_edit (Json.Node node_id, Json.Object root) {
        var result = new Json.Object ();
        bool applied = false;
        string reason = "";

        try {
            if (root.has_member ("params")) {
                var params_obj = root.get_object_member ("params");
                if (params_obj.has_member ("edit")) {
                    var edit = params_obj.get_member ("edit");
                    if (edit.get_node_type () == Json.NodeType.OBJECT) {
                        var edits_map = this.parse_workspace_edit (edit);
                        if (edits_map != null && !edits_map.is_empty) {
                            foreach (var entry in edits_map.entries) {
                                this.session.document_manager.apply_edits_to_file (entry.key, entry.value);
                            }
                            applied = true;
                        }
                    }
                }
            }
        } catch (GLib.Error e) {
            reason = e.message;
            this.logger.error ("LSP", "workspace/applyEdit from '%s' failed: %s".printf (this.name (), e.message));
        }

        result.set_boolean_member ("applied", applied);
        if (reason != "")
            result.set_string_member ("reason", reason);

        var result_node = new Json.Node (Json.NodeType.OBJECT);
        result_node.set_object (result);

        try {
            yield this.send_response_async (node_id, result_node);
        } catch (GLib.Error e) {
            this.logger.warning ("LSP", "Failed to respond to workspace/applyEdit: %s".printf (e.message));
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
                    diagnostics_service.update_diagnostics (this.name (), uri, diag_list);

                    this.diagnostics_received (this.name (), uri, diag_list);
                    return Source.REMOVE;
                });
            }
            break;

        case "$/progress" :
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

    /////////////////////////////////////////////////////////////
    // Requests

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

        this.open_documents.add (uri);

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

    public async void send_did_change (string uri, int version, Gee.List<PendingChange> changes) throws Error {
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

        this.open_documents.remove (uri);
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
        logger.info("DS", Json.to_string (node, true));


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
     * Запрос codeAction/resolve: догружаем поле edit для действия, которое
     * сервер (clangd) прислал без правок, но с полем data. [INDEX]
     */
    public async LspCodeActionResult? request_code_action_resolve (Json.Object data) throws Error {
        var response = yield this.send_request ("codeAction/resolve", data);

        if (response == null || !response.has_member ("result")) return null;

        var result_node = response.get_member ("result");
        if (result_node.get_node_type () == Json.NodeType.NULL) return null;
        // Результат resolve — это один объект CodeAction (не массив)
        if (result_node.get_node_type () != Json.NodeType.OBJECT) return null;

        var res = new LspCodeActionResult ();
        res.actions = new Gee.ArrayList<LspCodeActionItem> ();
        res.actions.add (parse_code_action (result_node.get_object ()));
        return res;
    }

    /**
     * Обработка серверного запроса workspace/diagnostic/refresh (LSP 3.17):
     * перезапрашивает pull-диагностику для всех документов, открытых на этом сервере.
     */
    private void request_diagnostic_refresh () {
        var uris = new string[this.open_documents.size];
        int i = 0;
        foreach (var uri in this.open_documents)
            uris[i++] = uri;

        foreach (var uri in uris) {
            this.request_pull_diagnostics.begin (uri, (obj, res) => {
                try {
                    this.request_pull_diagnostics.end (res);
                } catch (GLib.Error e) {
                    this.logger.debug ("LSP", "diagnostic/refresh pull for '%s' failed: %s".printf (uri, e.message));
                }
            });
        }
    }

    /**
     * RPC-запрос Pull-диагностики по спецификации LSP 3.17 (textDocument/diagnostic)
     */
    public async void request_pull_diagnostics (string uri) throws Error {
        var params = new Json.Object ();
        
        var doc = new Json.Object ();
        doc.set_string_member ("uri", uri);
        params.set_object_member ("textDocument", doc);

        // По спецификации можно передавать previousResultId для инкрементальной диагностики,
        // но для начала запросим полную (Full) диагностику текущего состояния
        
        // Отправляем запрос через нашу атомарную трубу
        var response = yield this.send_request ("textDocument/diagnostic", params);

        if (response == null || !response.has_member ("result")) return;

        var result_node = response.get_member ("result");
        if (result_node.get_node_type () != Json.NodeType.OBJECT) return;

        var result_obj = result_node.get_object ();
        
        // Сервер возвращает объект с полем "kind": "full" или "unchanged"
        string kind = result_obj.has_member ("kind") ? result_obj.get_string_member ("kind") : "";

        if (kind == "full" && result_obj.has_member ("items")) {
            var json_array = result_obj.get_array_member ("items");

            // Парсим JSON-массив в список ваших объектов IdeLspDiagnostic
            var diag_list = this.parse_diagnostics (json_array);

            // Передаем в главный поток для UI
            Idle.add (() => {
                // Передаем данные в глобальную модель
                diagnostics_service.update_diagnostics (this.name (), uri, diag_list);

                this.diagnostics_received (this.name (), uri, diag_list);
                return Source.REMOVE;
            });
        }
    }

    /**
     * RPC-ЗАПРОС УТОЧНEНИЯ ЭЛEМEНТА ПОДСКАЗКИ (LSP completionItem/resolve)
     * Принимает сырой JSON-объект CompletionItem, сохраненный при парсинге,
     * и возвращает обновленный объект с дозаполненными полями импорта/документации
     */
    public async Gee.ArrayList<Iide.LspTextEdit>? request_completion_item_resolve (Json.Object raw_item_node) throws Error {
        if (this.current_process == null || this.status != LspClientStatus.READY) {
            return null;
        }

        // По спецификации LSP, параметрами для 'completionItem/resolve' является 
        // сам исходный объект CompletionItem целиком, БEЗ дополнительных оберток!
        var response = yield this.send_request ("completionItem/resolve", raw_item_node);

        // Проверяем валидность ответа
        if (response == null || !response.has_member ("result")) {
            return null;
        }

        var result_node = response.get_member ("result");
        if (result_node.get_node_type () != Json.NodeType.OBJECT) {
            return null;
        }

        // Возвращаем дозаполненный объект JSON
        return this.parse_text_edits_array (result_node);
    }

    /**
     * RPC-ЗАПРОС ФОРМАТИРОВАНИЯ ДОКУМЕНТА (LSP textDocument/formatting)
     * Отправляет текущие настройки табуляции редактора и возвращает 
     * массив правок TextEdit[] для всего файла
     */
    public async Gee.ArrayList<Iide.LspTextEdit>? request_formatting (string uri, int tab_size, bool insert_spaces) throws Error {
        if (this.current_process == null || this.status != LspClientStatus.READY) {
            return null;
        }

        var params = new Json.Object ();

        // 1. Указываем документ
        var doc = new Json.Object ();
        doc.set_string_member ("uri", uri);
        params.set_object_member ("textDocument", doc);

        // 2. Формируем объект опций форматирования по спецификации LSP
        var options = new Json.Object ();
        options.set_int_member ("tabSize", tab_size);
        options.set_boolean_member ("insertSpaces", insert_spaces);
        params.set_object_member ("options", options);

        // Отправляем запрос через нашу стерильную асинхронную трубу
        var response = yield this.send_request ("textDocument/formatting", params);

        if (response == null || !response.has_member ("result")) {
            return null;
        }

        var result_node = response.get_member ("result");
        if (result_node.get_node_type () == Json.NodeType.NULL) {
            return null;
        }

        // Используем наш универсальный Си-парсер массивов правок!
        return this.parse_text_edits_array (result_node);
    }

    /**
     * RPC-ЗАПРОС ПЕРЕИМЕНОВАНИЯ СИМВОЛА (LSP textDocument/rename)
     * Отправляет позицию курсора и новое имя, возвращает карту правок
     * WorkspaceEdit: [uri] -> [массив TextEdit]
     */
    public async Gee.HashMap<string, Gee.ArrayList<LspTextEdit>>? request_rename (string uri, int line, int character, string new_name) throws Error {
        if (this.current_process == null || this.status != LspClientStatus.READY) {
            return null;
        }

        var params = new Json.Object ();

        // 1. Указываем документ
        var doc = new Json.Object ();
        doc.set_string_member ("uri", uri);
        params.set_object_member ("textDocument", doc);

        // 2. Указываем позицию курсора
        var pos = new Json.Object ();
        pos.set_int_member ("line", line);
        pos.set_int_member ("character", character);
        params.set_object_member ("position", pos);

        // 3. Новое имя символа
        params.set_string_member ("newName", new_name);

        // Отправляем запрос через нашу асинхронную трубу
        var response = yield this.send_request ("textDocument/rename", params);

        if (response == null || !response.has_member ("result")) {
            return null;
        }

        var result_node = response.get_member ("result");
        if (result_node.get_node_type () == Json.NodeType.NULL) {
            return null;
        }

        return this.parse_workspace_edit (result_node);
    }

    /**
     * RPC-ЗАПРОС workspace/willRenameFiles (LSP 3.16+)
     * Спрашивает сервер перед переименованием файла: сервер может
     * вернуть WorkspaceEdit с правками (например, обновить ссылки/импорты).
     * Возвращает null, если правок нет или сервер их не поддерживает.
     */
    public async Gee.HashMap<string, Gee.ArrayList<LspTextEdit>>? request_will_rename_files (string old_uri, string new_uri) throws Error {
        if (this.current_process == null || this.status != LspClientStatus.READY) {
            return null;
        }

        var params = new Json.Object ();
        var files = new Json.Array ();
        var file = new Json.Object ();
        file.set_string_member ("oldUri", old_uri);
        file.set_string_member ("newUri", new_uri);
        files.add_object_element (file);
        params.set_array_member ("files", files);

        var response = yield this.send_request ("workspace/willRenameFiles", params);

        if (response == null || !response.has_member ("result")) {
            return null;
        }

        var result_node = response.get_member ("result");
        if (result_node.get_node_type () == Json.NodeType.NULL) {
            return null;
        }

        return this.parse_workspace_edit (result_node);
    }

    /**
     * RPC-УВЕДОМЛЕНИЕ workspace/didRenameFiles (LSP 3.16+)
     * Оповещает сервер о свершившемся переименовании файла.
     */
    public async void notify_did_rename_files (string old_uri, string new_uri) throws Error {
        if (this.current_process == null || this.status != LspClientStatus.READY) {
            return;
        }

        var params = new Json.Object ();
        var files = new Json.Array ();
        var file = new Json.Object ();
        file.set_string_member ("oldUri", old_uri);
        file.set_string_member ("newUri", new_uri);
        files.add_object_element (file);
        params.set_array_member ("files", files);

        yield this.send_notification_async ("workspace/didRenameFiles", params);
    }

    /////////////////////////////////////////////////////////////
    // Parse responses helpers

    private void parse_capabilities (Json.Object result) {
        if (!result.has_member ("capabilities"))
            return;
        
        var caps = result.get_object_member ("capabilities");

        if (LspFeatures.DIAGNOSTICS in this.features) {
            this.capabilities.diagnostics_provider = LspDiagnosticMode.PUSH;
            if (caps.has_member ("diagnosticProvider")) {
                this.capabilities.diagnostics_provider = LspDiagnosticMode.PULL;
            }
        }

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
        if (LspFeatures.COMPLETION in this.features) {
            if (caps.has_member ("completionProvider")) {
                this.capabilities.completion_provider = true;
                var comp = caps.get_object_member ("completionProvider");
                if (comp.has_member ("triggerCharacters")) {
                    var triggers = comp.get_array_member ("triggerCharacters");
                    this.capabilities.completion_triggers.clear ();
                    foreach (var node in triggers.get_elements ()) {
                        this.capabilities.completion_triggers.add (node.get_string ());
                    }
                }
            }
        }

        // Hover & Definition
        this.capabilities.definition_provider = LspFeatures.DEFINTION in this.features && caps.has_member ("definitionProvider");
        this.capabilities.hover_provider = LspFeatures.HOVER in this.features && caps.has_member ("hoverProvider");
        this.capabilities.code_actions_provider = LspFeatures.CODE_ACTIONS in this.features && caps.has_member ("codeActionProvider");
        // RenameProvider может быть булевым флагом или объектом { prepareProvider: boolean } [INDEX]
        this.capabilities.rename_provider = LspFeatures.RENAME in this.features && caps.has_member ("renameProvider");

        bool server_support_formating = false;
        if (caps.has_member ("documentFormattingProvider")) {
            var format_node = caps.get_member ("documentFormattingProvider");
            var node_type = format_node.get_node_type ();

            // Кейс А: Сервер вернул простой булевый флаг (например, true) [INDEX]
            if (node_type == Json.NodeType.VALUE) {
                server_support_formating = format_node.get_boolean ();
            }
            // Кейс Б: Сервер вернул объект DocumentFormattingOptions { workDoneProgress?: boolean } [INDEX]
            else if (node_type == Json.NodeType.OBJECT) {
                server_support_formating = true; // Раз объект есть, фича поддерживается! [INDEX]
            }
        }
        this.capabilities.formatting_provider = LspFeatures.FORMATTING in this.features && server_support_formating;

        // Workspace file operations: willRenameFiles / didRenameFiles [INDEX]
        if (caps.has_member ("workspace")) {
            var ws_caps = caps.get_object_member ("workspace");
            if (ws_caps.has_member ("fileOperations")) {
                var file_ops = ws_caps.get_object_member ("fileOperations");
                this.capabilities.will_rename_files_provider = file_ops.has_member ("willRename");
                this.capabilities.did_rename_files_provider = file_ops.has_member ("didRename");
            }
        }
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

            d.server_name = this.name ();

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

                item.raw_json = item_obj;

                item.label = item_obj.get_string_member ("label");

                // Опциональные поля.
                // ВАЖНО: insert_text не должен наследоваться из label — серверы вроде
                // clangd декорируют label (ведущий пробел / маркер "•" вставки #include).
                // Предпочитаем textEdit.newText, затем insertText, и лишь в крайнем случае label.
                if (item_obj.has_member ("insertText"))
                    item.insert_text = item_obj.get_string_member ("insertText");
                else if (item_obj.has_member ("textEdit")) {
                    var te_node = item_obj.get_member ("textEdit");
                    if (te_node.get_node_type () == Json.NodeType.OBJECT
                        && te_node.get_object ().has_member ("newText")) {
                        item.insert_text = te_node.get_object ().get_string_member ("newText");
                    } else {
                        item.insert_text = item.label;
                    }
                } else
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

                if (item_obj.has_member ("additionalTextEdits")) {
                    var edits_node = item_obj.get_member ("additionalTextEdits");
                    // Вызываем ваш готовый метод, парсящий Json.Node в Gee.ArrayList<LspTextEdit>
                    item.additional_text_edits = this.parse_text_edits_array (edits_node);
                }

                res.items.add (item);
            }
        }

        return res;
    }

    public Gee.ArrayList<Iide.LspTextEdit> parse_text_edits_array (Json.Node node) {
        var res = new Gee.ArrayList<Iide.LspTextEdit> ();

        // Защитный барьер: если сервер прислал null или пустой узел — безопасно выходим
        if (node == null || node.get_node_type () == Json.NodeType.NULL) {
            return res;
        }

        Json.Array? edits_array = null;

        // Кейс 1: Сервер прислал чистый массив правок [TextEdit, TextEdit, ...]
        if (node.get_node_type () == Json.NodeType.ARRAY) {
            edits_array = node.get_array ();
        }
        // Кейс 2: На случай, если узел обернут в JSON-объект (для совместимости с некоторыми серверами)
        else if (node.get_node_type () == Json.NodeType.OBJECT) {
            var obj = node.get_object ();
            if (obj.has_member ("additionalTextEdits")) {
                var member_node = obj.get_member ("additionalTextEdits");
                if (member_node.get_node_type () == Json.NodeType.ARRAY) {
                    edits_array = member_node.get_array ();
                }
            }
        }

        if (edits_array == null) {
            return res;
        }

        // Перебираем элементы массива TextEdit
        foreach (var edit_node in edits_array.get_elements ()) {
            if (edit_node.get_node_type () != Json.NodeType.OBJECT) {
                continue;
            }

            var edit_obj = edit_node.get_object ();
            
            // Железное требование спецификации LSP: TextEdit обязан содержать поля 'range' и 'newText'
            if (!edit_obj.has_member ("range") || !edit_obj.has_member ("newText")) {
                continue;
            }

            var text_edit = new Iide.LspTextEdit ();
            text_edit.new_text = edit_obj.get_string_member ("newText");

            var range_obj = edit_obj.get_object_member ("range");
            if (range_obj == null) {
                continue;
            }

            // Извлекаем стартовые и финальные координаты диапазона правки
            var start = range_obj.get_object_member ("start");
            var end = range_obj.get_object_member ("end");

            if (start != null && end != null) {
                text_edit.start_line = (int) start.get_int_member ("line");
                text_edit.start_char = (int) start.get_int_member ("character");
                text_edit.end_line = (int) end.get_int_member ("line");
                text_edit.end_char = (int) end.get_int_member ("character");

                res.add (text_edit);
            }
        }

        return res;
    }

    /**
     * Парсер результата WorkspaceEdit (для textDocument/rename).
     * Поддерживает оба формата спецификации LSP:
     *  - "changes":      { [uri]: TextEdit[] }
     *  - "documentChanges": [ TextDocumentEdit { textDocument: {...}, edits: TextEdit[] }, ... ]
     * @return Карта [uri] -> [массив правок], либо null если разобрать не удалось
     */
    private Gee.HashMap<string, Gee.ArrayList<LspTextEdit>>? parse_workspace_edit (Json.Node node) {
        if (node == null || node.get_node_type () != Json.NodeType.OBJECT) {
            return null;
        }

        var result = new Gee.HashMap<string, Gee.ArrayList<LspTextEdit>> ();
        var edit_obj = node.get_object ();

        // Формат 1: "changes" — простая карта URI -> TextEdit[]
        if (edit_obj.has_member ("changes")) {
            var changes_obj = edit_obj.get_object_member ("changes");
            foreach (string file_uri in changes_obj.get_members ()) {
                var edits_node = changes_obj.get_member (file_uri);
                if (edits_node.get_node_type () != Json.NodeType.ARRAY) {
                    continue;
                }
                var edits_list = this.parse_text_edits_array (edits_node);
                if (!edits_list.is_empty) {
                    result.set (file_uri, edits_list);
                }
            }
        }

        // Формат 2: "documentChanges" — массив TextDocumentEdit (или операций с файлами)
        if (edit_obj.has_member ("documentChanges")) {
            var doc_changes = edit_obj.get_array_member ("documentChanges");
            foreach (var change_node in doc_changes.get_elements ()) {
                if (change_node.get_node_type () != Json.NodeType.OBJECT) {
                    continue;
                }
                var change_obj = change_node.get_object ();

                // Интересует только TextDocumentEdit (не CreateFile/RenameFile/DeleteFile)
                if (change_obj.has_member ("textDocument") && change_obj.has_member ("edits")) {
                    var text_doc = change_obj.get_object_member ("textDocument");
                    if (text_doc.has_member ("uri")) {
                        string file_uri = text_doc.get_string_member ("uri");
                        var edits_node = change_obj.get_member ("edits");
                        var edits_list = this.parse_text_edits_array (edits_node);

                        // Несколько TextDocumentEdit для одного файла — объединяем списки
                        if (result.has_key (file_uri)) {
                            result.get (file_uri).add_all (edits_list);
                        } else if (!edits_list.is_empty) {
                            result.set (file_uri, edits_list);
                        }
                    }
                }
            }
        }

        return result.is_empty ? null : result;
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
     * Парсер ответа CodeAction[] от LSP-сервера
     */
    private LspCodeActionResult parse_code_action_result (Json.Node node) {
        var res = new LspCodeActionResult ();
        res.actions = new Gee.ArrayList<LspCodeActionItem> ();

        if (node.get_node_type () != Json.NodeType.ARRAY) return res;
        var actions_array = node.get_array ();

        foreach (var action_node in actions_array.get_elements ()) {
            if (action_node.get_node_type () != Json.NodeType.OBJECT) continue;
            res.actions.add (parse_code_action (action_node.get_object ()));
        }

        return res;
    }

    /**
     * Парсер одиночного CodeAction (используется и для codeAction/resolve).
     */
    private LspCodeActionItem parse_code_action (Json.Object action_obj) {
        var item = new LspCodeActionItem ();

        // Читаем базовые поля [INDEX]
        item.title = action_obj.get_string_member ("title");
        if (action_obj.has_member ("kind")) {
            item.kind = action_obj.get_string_member ("kind");
        }

        // Сохраняем поле data для последующего codeAction/resolve [INDEX]
        if (action_obj.has_member ("data")) {
            var data_node = new Json.Node (Json.NodeType.OBJECT);
            data_node.set_object (action_obj.get_object_member ("data"));
            item.data = data_node.copy ().get_object ();
        }

        // Читаем структуру изменений WorkspaceEdit (edit.changes) [INDEX]
        if (action_obj.has_member ("edit")) {
            var edit_obj = action_obj.get_object_member ("edit");
            parse_workspace_edit_into (edit_obj, item);
        }

        // clangd шлёт часть действий (например, 'Apply fix: remove #include
        // directive') не с полем edit, а как Command: правка лежит в
        // arguments[0] в виде готового WorkspaceEdit. Разбираем и её. [INDEX]
        if (action_obj.has_member ("command") && action_obj.has_member ("arguments")) {
            var args_array = action_obj.get_array_member ("arguments");
            if (args_array.get_length () > 0) {
                var first_arg = args_array.get_element (0);
                if (first_arg.get_node_type () == Json.NodeType.OBJECT) {
                    var first_obj = first_arg.get_object ();
                    if (first_obj.has_member ("changes") || first_obj.has_member ("documentChanges")) {
                        parse_workspace_edit_into (first_obj, item);
                    }
                }
            }
        }

        return item;
    }

    /**
     * Разбор WorkspaceEdit (changes / documentChanges) в карту правок действия.
     */
    private void parse_workspace_edit_into (Json.Object edit_obj, LspCodeActionItem item) {
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

        // documentChanges (массив TextDocumentEdit): текстDocument.uri + edits [INDEX]
        if (edit_obj.has_member ("documentChanges")) {
            var dc_array = edit_obj.get_array_member ("documentChanges");
            foreach (var dc_node in dc_array.get_elements ()) {
                if (dc_node.get_node_type () != Json.NodeType.OBJECT) continue;
                var dc_obj = dc_node.get_object ();
                if (!dc_obj.has_member ("textDocument") || !dc_obj.has_member ("edits")) continue;

                var td = dc_obj.get_object_member ("textDocument");
                var file_uri = td.get_string_member ("uri");
                var edits_array = dc_obj.get_array_member ("edits");
                var edits_list = new Gee.ArrayList<LspTextEdit> ();

                foreach (var edit_node in edits_array.get_elements ()) {
                    if (edit_node.get_node_type () != Json.NodeType.OBJECT) continue;
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

                if (!item.changes.has_key (file_uri)) {
                    item.changes.set (file_uri, edits_list);
                } else {
                    item.changes.get (file_uri).add_all (edits_list);
                }
            }
        }
    }

    /**
     * ЗАВЕРШЕНИЕ РАБОТЫ LSP-СЕРВЕРА
     */
    public async void shutdown_and_exit_async (bool force_abort = true) {
        if (this.current_process == null) {
            this.status = LspClientStatus.STOPPED;
            return;
        }

        // 1. ВЗВОДИМ ЩИТ: Блокируем ложные срабатывания сигналов crashed во время тушения!
        this.is_stopping = true;

        this.logger.info ("LSP", "Sending protocol 'shutdown' request to '%s'...".printf (this.name ()));

        try {
            // 2. ФАЗА 1: Протокольное рукопожатие выключения (Обязано идти через yield!) [INDEX]
            // Мы даем серверу шанс сохранить свои кэши индексов на диск
            var reply = yield this.send_request ("shutdown", new Json.Object ());
            
            if (reply != null) {
                this.logger.debug ("LSP", "Server '%s' acknowledged shutdown request.".printf (this.name ()));
            }

            // 3. ФАЗА 2: Отправка уведомления на физический выход [INDEX]
            yield this.send_notification_async ("exit", new Json.Object ());
            
        } catch (GLib.Error e) {
            // Игнорируем ошибки сети: если сервер упал прямо во время shutdown — это нормально
            this.logger.warning ("LSP", "Network error during protocol shutdown: " + e.message);
        }

        // ===================================================================
        // 4. ФАЗА 3: СТEРИЛИЗАЦИЯ ЗАВИСШИХ ОБEЩАНИЙ (Promises Clean)
        // Если в момент тушения в мапе висели асинхронные запросы, 
        // которые спали на yield и ждали ответа от сокета — мы обязаны их разбудить!
        // ===================================================================
        if (!this.pending_requests.is_empty) {
            this.logger.debug ("LSP", "Evicting %d outstanding request(s) during shutdown.".printf (this.pending_requests.size));
            
            var aborted_ids = new Gee.ArrayList<int> ();
            foreach (int id in this.pending_requests.keys) {
                aborted_ids.add (id);
            }

            foreach (int id in aborted_ids) {
                if (this.pending_requests.has_key (id)) {
                    var promise = this.pending_requests.get (id);
                    this.pending_requests.unset (id);
                    this.cancel_request_timeout (promise);
                    
                    // Записываем ошибку отмены, чтобы send_request выкинул исключение
                    var err_obj = new Json.Object ();
                    var err_details = new Json.Object ();
                    err_details.set_string_member ("message", "LSP server forcefully stopped by user.");
                    err_obj.set_object_member ("error", err_details);
                    this.responses.set (id, err_obj);

                    // Будим уснувший метод в UI-потоке [INDEX]
                    Idle.add ((owned) promise.callback);
                }
            }
            
            this.pending_requests.clear ();
            this.responses.clear ();
        }

        // 5. ФАЗА 4: НИЗКОУРОВНEВОE ТУШEНИE ТРАНСПОРТА ОС
        // Просим LspProcess отменить Cancellable, дождаться смерти читателей 
        // и закрыть Си-дескрипторы пайпов stdin/stdout/stderr [INDEX, INDEX]
        yield this.current_process.terminate_async ();

        // СНОСИМ ССЫЛКУ: Полностью выкидываем старый объект процесса на съедение GC [INDEX]
        this.current_process = null;

        // Переводим конечный автомат в стабильную финальную точку
        this.status = force_abort ? LspClientStatus.ABORTED : LspClientStatus.STOPPED;
        this.is_stopping = false;
        
        this.logger.info ("LSP", "Server '%s' has been cleanly disconnected and stopped.".printf (this.name ()));
    }
}