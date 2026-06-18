using GLib;
using Gee;

public class Iide.LspService : GLib.Object {
    private static LspService? _instance;
    private Gee.HashMap<string, LspClient> clients;
    private Gee.HashMap<string, Gee.ArrayList<LspClient>> active_languages;

    private LoggerService logger;
    private LanguageRegistry registry;

    public signal void diagnostics_updated (string server_name, string uri, ArrayList<LspDiagnosticPair?> diagnostics);

    // [ClientHash] -> [Token] -> LspTaskInfo
    private Gee.HashMap<string, Gee.HashMap<string, LspTaskInfo?>> progress_map =
        new Gee.HashMap<string, Gee.HashMap<string, LspTaskInfo?>> ();

    public signal void tasks_changed (Gee.List<LspTaskInfo?> active_tasks);
    public signal void client_registered (LspClient client);

    construct {
        clients = new Gee.HashMap<string, LspClient> ();
        active_languages = new Gee.HashMap<string, Gee.ArrayList<LspClient>> ();
        logger = LoggerService.get_instance ();
        registry = LanguageRegistry.get_instance ();
    }

    public Gee.HashMap<string, LspClient> get_active_clients () {
        return this.clients;
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

    public LspClient[] get_clients () {
        return clients.values.to_array ();
    }

    public void clear_lsp_tasks () {
        progress_map.clear ();
        emit_tasks_changed ();
    }

    public void register_monitored_client (LspClient client) {
        string server_name = client.name ();

        client.progress_updated.connect ((token, msg, perc, active) => {
            if (!progress_map.has_key (server_name))
                progress_map.set (server_name, new Gee.HashMap<string, LspTaskInfo?> ());

            var client_tasks = progress_map.get (server_name);

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

    public void register_document (string language_id, string? workspace_root, SourceView view) {
        Gee.ArrayList<LspClient>? active_language_clients = this.active_languages.get (language_id);
        if (active_language_clients != null) {
            view.set_expected_lsp_clients (active_language_clients.size);
            foreach (var lsp_client in active_language_clients) {
                lsp_client.register_document (language_id, ((GtkSource.Buffer) view.buffer).text, workspace_root, view);
            }
            return;
        }

        var router = this.registry.get_router_for_language (language_id);
        if (router == null) {
            view.set_expected_lsp_clients (0);
            logger.info ("LSP", "No LSP router/servers configured for language: %s".printf (language_id));
            return;
        }

        // 2. Извлекаем ВСЕ уникальные серверы, которые должны обслуживать этот язык
        Gee.Set<string> assigned_servers = router.get_all_assigned_servers ();
        var new_clients = new Gee.ArrayList<LspClient> ();
        var existing_clients = new Gee.ArrayList<LspClient> ();
        var language_clients = new Gee.ArrayList<LspClient> ();
        foreach (var server_name in assigned_servers) {
            if (this.clients.has_key (server_name)) {
                var client = this.clients.get (server_name);
                existing_clients.add (client);
                language_clients.add (client);
            } else {
                // Извлекаем честный, смерженный LspConfig из реестра!
                var server_config = registry.get_config_for_server (server_name);
                if (server_config != null) {
                    var new_client = new LspClient (server_config, router.features_for_server_name (server_name));
                    new_client.diagnostics_received.connect ((server_name, diag_uri, diagnostics) => {
                        this.diagnostics_updated (server_name, diag_uri, diagnostics);
                    });
                    this.client_registered (new_client);
                    this.clients.set (server_name, new_client);
                    new_clients.add (new_client);
                    language_clients.add (new_client);
                }
            }
        }

        var expected_lsp_clients_count = language_clients.size;
        view.set_expected_lsp_clients (expected_lsp_clients_count);

        if (expected_lsp_clients_count == 0)
            return;

        this.active_languages.set (language_id, language_clients);

        foreach (var lsp_client in language_clients) {
            lsp_client.register_document (language_id, ((GtkSource.Buffer) view.buffer).text, workspace_root, view);
        }

        foreach (var new_lsp_client in new_clients) {
            new_lsp_client.start_server_async.begin (workspace_root);
        }
    }

    /**
     * Асинхронно и параллельно остановить все активные LSP-серверы текущего проекта
     */
    public async void shutdown_all_running_lsp_servers_async () {
        if (this.clients.size == 0) return;

        this.logger.info ("LSP", @"Shutting down $(this.clients.size) active LSP servers...");

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
        this.active_languages.clear ();
        this.logger.info ("LSP", "All LSP servers are cleanly stopped and cleared from memory.");
    }
}