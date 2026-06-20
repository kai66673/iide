/*
*/

public delegate bool Iide.ProviderPredicate(LspClientSyncer item);

public class Iide.LspDocumentClient: GLib.Object {
    private SourceView source_view;
    private LoggerService logger;
        
    // Список всех активных и зарегистрированных серверов для этой вкладки
    public Gee.ArrayList<LspClientSyncer> clients = new Gee.ArrayList<LspClientSyncer> ();

    private string tooltip_separator = "────────────────────────────────────────";

    public LspDocumentClient(SourceView source_view) {
        Object();
        this.source_view = source_view;
        this.logger = LoggerService.get_instance ();
    }

    public Gee.ArrayList<LspClientSyncer> active_clients (ProviderPredicate? predicate = null) { 
        var result = new Gee.ArrayList<LspClientSyncer> ();
        foreach (var client in clients) {
            if (client.document_added && client.is_ready) {
                if (predicate != null && predicate(client)) {
                    result.add (client);
                }
            }
        }
        return result;
    }

    public void register_lsp_clients (Gee.ArrayList<LspClient> clients) {
        foreach (var client in clients) {
            this.clients.add (new LspClientSyncer (this.source_view, client));
        }
    }

    public void add_change (PendingChange new_change) {
        foreach (var client in clients) {
            client.add_change (new_change);
        }
    }

    public void flush_changes () {
        foreach (var client in clients) {
            client.flush_changes ();
        }
    }

    public async void flush_changes_async () {
        foreach (var client in clients) {
            yield client.flush_changes_async ();
        }
    }
    
    ////////
    public void save_document() {
        foreach (var lsp_client in this.active_clients ()) {
            lsp_client.client.text_document_did_change.begin (
                this.source_view.uri,
                lsp_client.document_version,
                ((GtkSource.Buffer) this.source_view.buffer).text
            );
        }
    }

    public async string ? request_hover (string uri, int line, int character) {
        this.flush_changes ();

        Gee.HashMap<string, string> hovers = new Gee.HashMap<string, string> ();

        // Получаем список серверов этой конкретной вкладки, поддерживающих Completion
        var active_servers = this.active_clients ((lsp_client) => {
            return lsp_client.client.capabilities.hover_provider;
        });

        if (active_servers.is_empty) {
            return "No information (no active LSP hover providers)...";
        }

        // Счетчик параллельно выполняющихся асинхронных RPC-запросов к сокетам ОС
        int active_requests = 0;
        SourceFunc resume_callback = request_hover.callback;

        foreach (var lsp_client in active_servers) {
            active_requests++;
            var client = lsp_client.client;

            client.request_hover.begin (uri, line, character, (obj, res) => {
                try {
                    var result = client.request_hover.end (res);
                    if (result != null) {
                        hovers.set (client.name (), result);
                    }

                } catch (GLib.Error e) {
                    this.logger.error ("LSP", "Hover request failed for '%s': %s".printf (client.name (), e.message));
                } finally {
                    active_requests--;
                    // Когда САМЫЙ последний сокет вернул данные — будим основной метод!
                    if (active_requests == 0) {
                        Idle.add ((owned) resume_callback);
                    }
                }
            });
        }

        // Засыпаем и отдаем управление MainContext, пока Ruff и Pyright параллельно качают пакеты
        yield;

        if (hovers.size == 0)
            return "No information...";

        var sb = new StringBuilder ();
        foreach (var hover in hovers.entries) {
            if (sb.len > 0) {
                sb.append ("\n" + tooltip_separator + "\n");
            }
            sb.append_printf ("<span>%s (%s)</span>", GLib.Markup.escape_text (hover.value), hover.key);
        }

        return sb.str;
    }

    public async Gee.ArrayList<LspCodeActionResult> request_code_actions (
        string uri,
        int start_line,
        int start_char,
        int end_line,
        int end_char,
        Json.Array diagnostics_json_array
    ) {
        var results = new Gee.ArrayList<LspCodeActionResult> ();

        // Получаем список серверов этой конкретной вкладки, поддерживающих Completion
        var active_servers = this.active_clients ((lsp_client) => {
            return lsp_client.client.capabilities.code_actions_provider;
        });

        if (active_servers.is_empty) {
            return results;
        }

        // Счетчик параллельно выполняющихся асинхронных RPC-запросов к сокетам ОС
        int active_requests = 0;
        SourceFunc resume_callback = request_code_actions.callback;

        foreach (var lsp_client in active_servers) {
            active_requests++;
            var client = lsp_client.client;

            client.request_code_actions.begin (uri, start_line, start_char, end_line, end_char, diagnostics_json_array, (obj, res) => {
                try {
                    var result = client.request_code_actions.end (res);
                    if (result != null) {
                        result.server_name = client.name ();
                        results.add (result);
                    }
                } catch (GLib.Error e) {
                    this.logger.error ("LSP", "Code actions request failed for '%s': %s".printf (client.name (), e.message));
                } finally {
                    active_requests--;
                    // Когда САМЫЙ последний сокет вернул данные — будим основной метод!
                    if (active_requests == 0) {
                        Idle.add ((owned) resume_callback);
                    }
                }
            });
        }

        // Засыпаем и отдаем управление MainContext, пока Ruff и Pyright параллельно качают пакеты
        yield;

        return results;
    }

    public async Gee.ArrayList<LspLocation>? request_definition (string uri, int line, int character) throws Error {
        var active_servers = this.active_clients ((lsp_client) => {
            return lsp_client.client.capabilities.definition_provider;
        });

        foreach (var lsp_client in active_servers) {
            return yield lsp_client.client.request_definition (uri, line, character);
        }
        return null;
    }
}