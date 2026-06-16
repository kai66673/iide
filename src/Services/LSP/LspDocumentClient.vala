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
}