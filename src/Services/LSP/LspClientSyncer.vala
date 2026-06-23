/*
*/
public class Iide.LspClientSyncer: GLib.Object {
    private SourceView source_view;
    public LspClient client { get; private set; }
    private LoggerService logger;

    private Gee.ArrayList<PendingChange> pending_queue = new Gee.ArrayList<PendingChange> ();
    public int document_version { get; private set; default = 0; }
    private uint debounce_id = 0;
    public bool document_added { get; private set; default = false; }

    public bool is_ready { get { return this.client.status == LspClientStatus.READY; } }

    public LspClientSyncer (SourceView source_view, LspClient client) {
        Object ();
        this.source_view = source_view;
        this.client = client;
        this.logger = LoggerService.get_instance ();

        this.client.state_ready_changed.connect (this.on_state_ready_changed);
        if (this.is_ready) {
            this.on_state_ready_changed (true);
        }
    }

    ~LspClientSyncer () {
        this.disconnect_signals ();
    }

    /**
     * Явная очистка ресурсов и таймеров для предотвращения утечек памяти и Си-крашей [INDEX]
     */
    public void disconnect_signals () {
        // 1. Начисто удаляем висящие таймеры дебаунса из MainLoop, чтобы они не выстрелили в пустоту
        if (this.debounce_id > 0) {
            Source.remove (this.debounce_id);
            this.debounce_id = 0;
        }

        // 2. ЖEЛEЗОБEТОННО ОТПИСЫВАEМСЯ ОТ СИГНАЛА СEРВEРА!
        // Теперь долгоживущий LspClient мгновенно отпустит Си-ссылку на этот синкер,
        // и объект чисто сотрется из памяти кучи без риска Use-After-Free [INDEX]!
        this.client.state_ready_changed.disconnect (this.on_state_ready_changed);
        
        this.pending_queue.clear ();
    }

    private void on_state_ready_changed (bool is_ready) {
        pending_queue = new Gee.ArrayList<PendingChange> ();
        if (debounce_id > 0) {
            Source.remove (debounce_id);
            debounce_id = 0;
        }
        this.document_version = 0;
        this.document_added = false;

        if (is_ready) {
            this.client.text_document_did_open.begin (
                this.source_view.uri,
                this.client.language_id,
                1,
                this.source_view.buffer.text,
                (obj, res) =>
            {
                try {
                    this.client.text_document_did_open.end (res);
                    this.document_added = true;
                    this.logger.info ("LSP", "Document %s opened in '%s'".printf (source_view.uri, this.client.name ()));
                } catch (GLib.Error e) {
                    this.logger.error ("LSP", "Document %s failed to open in '%s'".printf (source_view.uri, this.client.name ()));
                }
            });
        }
    }

    public void add_change (PendingChange new_change) {
        if (!this.document_added || this.client.status != LspClientStatus.READY)
            return;
        
        if (!pending_queue.is_empty) {
            // TODO: merge changes...
        }

        this.document_version++;
        pending_queue.add (new_change);
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

        if (!this.document_added || this.client.status != LspClientStatus.READY)
            return;

        switch (this.client.capabilities.sync_kind) {
            case TextDocumentSyncKind.FULL:
                this.client.text_document_did_change.begin (
                    this.source_view.uri, this.document_version, this.source_view.buffer.text, (obj, res) =>
                {
                    if (this.client.capabilities.diagnostics_provider == LspDiagnosticMode.PULL) {
                        this.client.request_pull_diagnostics.begin (this.source_view.uri);
                    }
                });
                break;
            case TextDocumentSyncKind.INCREMENTAL:
                this.client.send_did_change.begin (
                    this.source_view.uri, this.document_version, changes, (obj, res) =>
                {
                    if (this.client.capabilities.diagnostics_provider == LspDiagnosticMode.PULL) {
                        this.client.request_pull_diagnostics.begin (this.source_view.uri);
                    }
                });
                break;
            case TextDocumentSyncKind.NONE:
                break;
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

        if (!this.document_added || this.client.status != LspClientStatus.READY)
            return;

        switch (this.client.capabilities.sync_kind) {
            case TextDocumentSyncKind.FULL:
                try {
                    yield this.client.text_document_did_change (this.source_view.uri, this.document_version, this.source_view.buffer.text);
                    if (this.client.capabilities.diagnostics_provider == LspDiagnosticMode.PULL) {
                        this.client.request_pull_diagnostics.begin (this.source_view.uri);
                    }
                } catch (GLib.Error e) {
                    this.logger.error ("LSP", "Error on send 'text_document_did_change' for document %s: %s".printf (this.source_view.uri, e.message));
                }
                break;
            case TextDocumentSyncKind.INCREMENTAL:
                try {
                    yield this.client.send_did_change (this.source_view.uri, this.document_version, changes);
                    if (this.client.capabilities.diagnostics_provider == LspDiagnosticMode.PULL) {
                        this.client.request_pull_diagnostics.begin (this.source_view.uri);
                    }
                } catch (GLib.Error e) {
                    this.logger.error ("LSP", "Error on send 'send_did_change' for document %s: %s".printf (this.source_view.uri, e.message));
                }
                break;
            case TextDocumentSyncKind.NONE:
                break;
        }
    }
}
