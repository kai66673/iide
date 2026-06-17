/*
*/

public class Iide.LspDocumentClient: GLib.Object {
    private SourceView source_view;
    private LoggerService logger;
        
    // Список всех активных и зарегистрированных серверов для этой вкладки
    public Gee.ArrayList<LspClient> active_clients = new Gee.ArrayList<LspClient> ();

    // Общее количество серверов, которое мы ожидаем из роутера lsp.json для этого файла
    private int expected_lsp_clients_count = -1;    // -1 - ожидаем

    private bool all_clients_started_or_failed = false;

    private Gee.ArrayList<PendingChange> pending_queue = new Gee.ArrayList<PendingChange> ();
    private int document_version = 0;
    private uint debounce_id = 0;

    private string tooltip_separator = "────────────────────────────────────────";

    public LspDocumentClient(SourceView source_view) {
        Object();
        this.source_view = source_view;
        this.logger = LoggerService.get_instance ();
    }

    public void add_change (PendingChange new_change) {
        if (!pending_queue.is_empty) {
            // TODO: merge changes...
        }

        if (this.expected_lsp_clients_count == 0)
            return;

        this.document_version++;
        pending_queue.add (new_change);

        if (this.all_clients_started_or_failed)
            reset_timer ();
    }

    private void reset_timer () {
        if (debounce_id > 0)
            Source.remove (debounce_id);
        debounce_id = Timeout.add (400, () => {
            flush_changes ();
            return Source.REMOVE;
        });
    }

    public void flush_changes () {
        if (pending_queue.is_empty)
            return;

        var changes = pending_queue;
        pending_queue = new Gee.ArrayList<PendingChange> ();
        if (debounce_id > 0) {
            Source.remove (debounce_id);
            debounce_id = 0;
        }

        foreach (var lsp_client in this.active_clients) {
            if (lsp_client.status != LspClientStatus.READY)
                continue;

            switch (lsp_client.capabilities.sync_kind) {
                case TextDocumentSyncKind.FULL:
                    lsp_client.text_document_did_change.begin (this.source_view.uri, this.document_version, this.source_view.buffer.text);
                    break;
                case TextDocumentSyncKind.INCREMENTAL:
                    lsp_client.send_did_change.begin (this.source_view.uri, this.document_version, changes);
                    break;
                case TextDocumentSyncKind.NONE:
                    break;
            }
        }
    }

    public async void flush_changes_async () {
        if (pending_queue.is_empty)
            return;

        var changes = pending_queue;
        pending_queue = new Gee.ArrayList<PendingChange> ();
        if (debounce_id > 0) {
            Source.remove (debounce_id);
            debounce_id = 0;
        }

        foreach (var lsp_client in this.active_clients) {
            if (lsp_client.status != LspClientStatus.READY)
                continue;

            switch (lsp_client.capabilities.sync_kind) {
                case TextDocumentSyncKind.FULL:
                    try {
                        yield lsp_client.text_document_did_change (this.source_view.uri, this.document_version, this.source_view.buffer.text);
                    } catch (GLib.Error e) {
                        this.logger.error ("LSP", "Error on send 'text_document_did_change' for document %s: %s".printf (this.source_view.uri, e.message));
                    }
                    break;
                case TextDocumentSyncKind.INCREMENTAL:
                    try {
                        yield lsp_client.send_did_change (this.source_view.uri, this.document_version, changes);
                    } catch (GLib.Error e) {
                        this.logger.error ("LSP", "Error on send 'send_did_change' for document %s: %s".printf (this.source_view.uri, e.message));
                    }
                    break;
                case TextDocumentSyncKind.NONE:
                    break;
            }
        }
    }
    
    /**
     * УНИВЕРСАЛЬНЫЙ БИНДИНГ НА ОСНОВЕ СТАТУСА КЛИЕНТА
     * Этот метод вызывается ВСЕГДА в асинхронном колбэке LspService.open_document() [INDEX].
     */
    public void bind_lsp_client (LspClient client) {
        if (this.active_clients.contains (client))
            return;  // Параноя!

        this.active_clients.add (client);
        this.logger.debug ("LSP", "Client '%s' with status %d added to document %s.".printf (client.name (), client.status, this.source_view.uri));

        if (this.active_clients.size == this.expected_lsp_clients_count) {
            this.all_clients_started_or_failed = true;
            this.flush_changes ();
        }
    }

    /**
     * Метод задания барьера ожидания.
     * Вызывается из view.set_expected_lsp_clients() в самом начале open_document.
     */
    public void set_expected_lsp_clients (int count) {
        this.expected_lsp_clients_count = count;
        this.logger.debug ("LSP", @"LspDocumentClient expects $count server(s) from project router.");
        
        if (count == 0) {
            this.pending_queue.clear ();
        } else if (this.expected_lsp_clients_count == this.active_clients.size) {
            this.all_clients_started_or_failed = true;
            this.flush_changes ();
        }
    }

    ////////
    public void save_document() {
        foreach (var lsp_client in this.active_clients) {
            lsp_client.text_document_did_change.begin (
                this.source_view.uri,
                this.document_version,
                ((GtkSource.Buffer) this.source_view.buffer).text
            );
        }
    }

    public async string ? request_hover (string uri, int line, int character) {
        this.flush_changes ();

        Gee.HashMap<string, string> hovers = new Gee.HashMap<string, string> ();

        // Получаем список серверов этой конкретной вкладки, поддерживающих Completion
        var active_servers = new Gee.ArrayList<LspClient> ();
        foreach (var client in active_clients) {
            // Берем только READY серверы, которые по lsp.json умеют автодополнение
            if (client.status == LspClientStatus.READY && client.capabilities.hover_provider) {
                active_servers.add (client);
            }
        }

        if (active_servers.is_empty) {
            return "No information (no avtive LSP providers)...";
        }

        // Счетчик параллельно выполняющихся асинхронных RPC-запросов к сокетам ОС
        int active_requests = 0;
        SourceFunc resume_callback = request_hover.callback;

        foreach (var client in active_servers) {
            active_requests++;

            client.request_hover.begin (uri, line, character, (obj, res) => {
                try {
                    var result = client.request_hover.end (res);
                    if (result != null) {
                        Idle.add (() => {
                            hovers.set (client.name (), result);
                            return Source.REMOVE;
                        });
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
        var active_servers = new Gee.ArrayList<LspClient> ();
        foreach (var client in active_clients) {
            // Берем только READY серверы, которые по lsp.json умеют автодополнение
            if (client.status == LspClientStatus.READY && client.capabilities.code_actions_provider) {
                active_servers.add (client);
            }
        }

        if (active_servers.is_empty) {
            return results;
        }

        // Счетчик параллельно выполняющихся асинхронных RPC-запросов к сокетам ОС
        int active_requests = 0;
        SourceFunc resume_callback = request_code_actions.callback;

        foreach (var client in active_servers) {
            active_requests++;

            client.request_code_actions.begin (uri, start_line, start_char, end_line, end_char, diagnostics_json_array, (obj, res) => {
                try {
                    var result = client.request_code_actions.end (res);
                    if (result != null) {
                        Idle.add (() => {
                            result.server_name = client.name ();
                            results.add (result);
                            return Source.REMOVE;
                        });
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
        foreach (var client in active_clients) {
            if (client.status == LspClientStatus.READY && client.capabilities.definition_provider) { 
                return yield client.request_definition (uri, line, character);
            }

        }
        return null;
    }
}