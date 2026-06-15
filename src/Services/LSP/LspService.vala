using GLib;
using Gee;

public class Iide.LspService : GLib.Object {
    private static LspService? _instance;
    private Gee.HashMap<string, LspClient> clients;
    private Gee.HashMap<string, string> uri_to_client_key;
    private Gee.HashMap<string, int> document_versions;
    private Gee.HashMap<string, bool> client_starting;

    private LoggerService logger = LoggerService.get_instance ();

    public signal void diagnostics_updated (string uri, ArrayList<LspDiagnosticPair?> diagnostics);

    // [ClientHash] -> [Token] -> LspTaskInfo
    private Gee.HashMap<int, Gee.HashMap<string, LspTaskInfo?>> progress_map =
        new Gee.HashMap<int, Gee.HashMap<string, LspTaskInfo?>> ();

    public signal void tasks_changed (Gee.List<LspTaskInfo?> active_tasks);

    construct {
        clients = new Gee.HashMap<string, LspClient> ();
        uri_to_client_key = new Gee.HashMap<string, string> ();
        document_versions = new Gee.HashMap<string, int> ();
        client_starting = new Gee.HashMap<string, bool> ();
    }

    public static unowned LspService get_instance () {
        if (_instance == null) {
            _instance = new LspService ();
        }
        return _instance;
    }

    public string ? get_language_id_for_file (GLib.File file) {
        string filename = file.get_basename () ?? "";

        switch (filename) {
        case "CMakeLists.txt" :
            return "cmake";
        case ".gitignore":
            return "git-config";
        case "meson.build":
            return "meson";
        case "PKGBUILD":
            return "bash";
        default:
            break;
        }

        string path = file.get_path () ?? "";
        int dot_pos = path.last_index_of (".");
        if (dot_pos >= 0 && dot_pos < path.length - 1) {
            string ext = path[dot_pos + 1 : path.length].down ();
            switch (ext) {
            case "py":
                return "python";
            case "c":
            case "h":
                return "c";
            case "cpp":
            case "cc":
            case "cxx":
            case "hpp":
            case "hxx":
                return "cpp";
            case "vala":
            case "vapi":
                return "vala";
            case "rs":
                return "rust";
            case "go":
                return "go";
            case "js":
            case "ts":
                return "javascript";
            case "json":
                return "json";
            case "xml":
                return "xml";
            case "html":
            case "htm":
                return "html";
            case "css":
                return "css";
            case "md":
            case "markdown":
                return "markdown";
            case "sh":
            case "bash":
            case "zsh":
                return "bash";
            case "yaml":
            case "yml":
                return "yaml";
            }
        }

        return null;
    }

    public LspClient ? get_client_by_hash (int client_id) {
        foreach (var client in clients.values) {
            if (client.get_hash () == client_id) {
                return client;
            }
        }
        return null;
    }

    public LspClient[] get_clients () {
        return clients.values.to_array ();
    }

    public void clear_lsp_tasks () {
        progress_map.clear ();
        emit_tasks_changed ();
    }

    public void register_client (LspClient client) {
        int id = client.get_hash ();

        client.progress_updated.connect ((token, msg, perc, active) => {
            if (!progress_map.has_key (id))
                progress_map.set (id, new Gee.HashMap<string, LspTaskInfo?> ());

            var client_tasks = progress_map.get (id);

            if (active) {
                var info = LspTaskInfo () {
                    server_name = client.name (),
                    message = msg,
                    percentage = perc
                };
                client_tasks.set (token, info);
            } else {
                client_tasks.unset (token);
            }

            emit_tasks_changed ();
        });
    }

    private void emit_tasks_changed () {
        var all_tasks = new Gee.ArrayList<LspTaskInfo?> ();
        foreach (var client_map in progress_map.values) {
            foreach (var task in client_map.values) {
                all_tasks.add (task);
            }
        }
        tasks_changed (all_tasks);
    }

    public async void open_document (string uri, string language_id, string content, string? workspace_root, SourceView view) {
        var server_key = language_id;
        LanguageProfile? lang_profile = LanguageRegistry.get_instance ().get_profile (language_id);

        if (lang_profile == null) {
            debug ("IdeLspService: No LSP server configured for language: %s", language_id);
            Idle.add (() => {
                view.bind_lsp_client (null);
                return Source.REMOVE;
            });
            return;
        }

        debug ("IdeLspService: Opening document %s (lang=%s)", uri, language_id);

        LspClient? client = null;

        // 1. Извлекаем клиент из кэша активных серверов
        if (this.clients.has_key (server_key)) {
            client = this.clients.get (server_key);
        } else {
            // 2. Если клиента еще нет — лениво создаем объект-оболочку 
            // (Сам процесс ОС будет запущен централизованно диспетчером воркспейса)
            var config = lang_profile.lsp;
            if (config == null) {
                Idle.add (() => {
                    view.bind_lsp_client (null);
                    return Source.REMOVE;
                });
                return;
            }

            client = new LspClient (config);
            
            client.diagnostics_received.connect ((uri, diagnostics) => {
                this.diagnostics_updated (uri, diagnostics);
            });

            this.clients.set (server_key, client);
        }

        // Синхронизируем внутренние мапы версий для вашей кодовой базы
        this.uri_to_client_key.set (uri, server_key);
        this.document_versions.set (uri, 1);

        // 3. Отдаем документ клиенту. Клиент внутри себя атомарно решает:
        //    Отправить didOpen по сети или положить в безопасный docs_snapshot!
        client.register_and_open_document (uri, language_id, 1, content);

        // 4. Привязываем бэкенд-клиент к графическому отображению SourceView
        Idle.add (() => {
            view.bind_lsp_client (client);
            return Source.REMOVE;
        });

        // 2. Старый способ запуска: если процесс сервера остановлен — будим его [INDEX]
        if (client.status == LspClientStatus.STOPPED) {
            // Метод .begin запускает ваш нативный start_async в изолированном фоне [INDEX]
            client.start_server_async.begin (workspace_root, (obj, res) => {
                if (!client.start_server_async.end (res)) {
                    Idle.add (() => {
                        view.bind_lsp_client (null);
                        return Source.REMOVE;
                    });
                }
            });
        }
    }

    public async void change_document (string uri, string content, int? change_start = null, int? change_end = null) {
        var server_key = uri_to_client_key.get (uri);

        logger.debug ("LSP", "Changed doc: " + uri + " / server_key: " + server_key);
        if (server_key == null || !clients.has_key (server_key)) {
            return;
        }

        var client = clients.get (server_key);
        var version = document_versions.get (uri);
        document_versions.set (uri, version + 1);

        try {
            yield client.text_document_did_change (uri, version + 1, content);
        } catch (Error e) {
            logger.error ("LSP", "Failed to change document (FULL sync) %s: %s".printf (uri, e.message));
        }
    }

    public async void send_did_change (string uri, int version, Gee.ArrayList<PendingChange> changes) {
        var server_key = uri_to_client_key.get (uri);
        if (server_key == null || !clients.has_key (server_key)) {
            return;
        }

        var client = clients.get (server_key);
        try {
            yield client.send_did_change (uri, version, changes);
        } catch (Error e) {
            logger.error ("LSP", "Failed to change document (INCREMENTAL sync) %s: %s".printf (uri, e.message));
        }
    }

    public async void close_document (string uri) {
        var server_key = uri_to_client_key.get (uri);
        if (server_key == null || !clients.has_key (server_key)) {
            return;
        }

        var client = clients.get (server_key);
        try {
            yield client.text_document_did_close (uri);
        } catch (Error e) {
            logger.error ("LSP", "Failed to close document %s: %s".printf (uri, e.message));
        }

        uri_to_client_key.unset (uri);
        document_versions.unset (uri);
    }

    public LspClient ? get_client_for_uri (string uri) {
        var server_key = uri_to_client_key.get (uri);
        if (server_key == null) {
            return null;
        }
        return clients.get (server_key);
    }
    public async LspCodeActionResult? request_code_actions (
        string uri,
        int start_line,
        int start_char,
        int end_line,
        int end_char,
        Json.Array diagnostics_json_array
    ) {
        var client = get_client_for_uri (uri);
        if (client == null) {
            return null;
        }
        try {
            return yield client.request_code_actions (uri, start_line, start_char, end_line, end_char, diagnostics_json_array);
        } catch (Error e) {
            logger.error ("LSP", "Failed to request code actions for %s: %s".printf (uri, e.message));
            return null;
        }
    }

    public async LspCompletionResult ? request_completion (
        string uri,
        int line,
        int character,
        string? trigger_character = null,
        CompletionTriggerKind trigger_kind = INVOKED
    ) {
        var client = get_client_for_uri (uri);
        if (client == null) {
            return null;
        }
        try {
            return yield client.request_completion (uri, line, character, trigger_character, trigger_kind);
        } catch (Error e) {
            logger.error ("LSP", "Failed to request completion for %s: %s".printf (uri, e.message));
            return null;
        }
    }

    public async string ? request_hover (string uri, int line, int character) {
        var client = get_client_for_uri (uri);
        if (client == null) {
            return null;
        }
        try {
            return yield client.request_hover (uri, line, character);
        } catch (Error e) {
            logger.error ("LSP", "Failed to request hover for %s: %s".printf (uri, e.message));
            return null;
        }
    }

    public async Gee.ArrayList<LspLocation>? goto_definition (string uri, int line, int character) {
        var client = get_client_for_uri (uri);
        if (client == null)
            return null;
        try {
            return yield client.request_definition (uri, line, character);
        } catch (Error e) {
            logger.error ("LSP", "Failed to request definition for %s: %s".printf (uri, e.message));
            return null;
        }
    }

    public async Gee.List<DocumentLspSymbol>? document_symbols(string uri) {
                var client = get_client_for_uri (uri);
        if (client == null)
            return null;
        try {
            return yield client.document_symbols (uri);
        } catch (Error e) {
            logger.error ("LSP", "Failed to request document symbols for %s: %s".printf (uri, e.message));
            return null;
        }
    }

    /**
     * Асинхронно и параллельно остановить все активные LSP-серверы текущего проекта
     */
    public async void shutdown_all_running_lsp_servers_async () {
        if (this.clients.size == 0) return;

        LoggerService.get_instance ().info ("LSP", @"Shutting down $(this.clients.size) active LSP servers...");

        // Шаг 1. Безопасно копируем клиентов во временный список для итерации [INDEX]
        var clients_to_stop = new Gee.ArrayList<LspClient> ();
        foreach (var client in this.clients.values) {
            clients_to_stop.add (client);
        }

        // Счетчик параллельно выполняющихся асинхронных закрытий
        int active_shutdowns = 0;
        
        // Запоминаем текущий асинхронный колбэк метода, чтобы разбудить его позже [INDEX]
        SourceFunc resume_callback = shutdown_all_running_lsp_servers_async.callback;

        // Шаг 2. Запускаем параллельное закрытие для каждого сервера [INDEX]
        foreach (var client in clients_to_stop) {
            active_shutdowns++;
            
            // Метод .begin запускает shutdown_and_exit_async в фоне и сразу возвращает управление [INDEX]
            client.shutdown_and_exit_async.begin ((obj, res) => {
                // Завершаем асинхронную операцию на уровне клиента
                client.shutdown_and_exit_async.end (res);
                
                active_shutdowns--;
                
                // Когда САМЫЙ последний сервер закончил отправку пакетов shutdown/exit — 
                // мы возвращаем управление в наш метод [INDEX]
                if (active_shutdowns == 0) {
                    Idle.add ((owned) resume_callback);
                }
            });
        }

        // Шаг 3. Засыпаем на этой строчке. 
        // Вся распределенная система серверов закрывается параллельно в фоне! [INDEX]
        yield;

        // Полностью очищаем карту клиентов. Сервис готов к работе со следующим проектом!
        this.clients.clear ();
        LoggerService.get_instance ().info ("LSP", "All LSP servers are cleanly stopped and cleared from memory.");
    }
}