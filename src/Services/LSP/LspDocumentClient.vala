/*
*/

public class Iide.LspDocumentClient: GLib.Object {
    private SourceView source_view;

    private Gee.ArrayList<PendingChange> pending_queue = new Gee.ArrayList<PendingChange> ();
    private int document_version = 0;
    private uint debounce_id = 0;
    private uint debounce_full_id = 0;
    private int lsp_sync_kind = 0; // 0 - не синхронизирован, 1 - incremental, 2 - full sync

    private ulong change_handler_id = 0;

    public LspDocumentClient(SourceView source_view) {
        this.source_view = source_view;
        this.source_view.changed.connect(add_change);
    }

    private void add_change (PendingChange nc) {
        if (!pending_queue.is_empty) {
            // TODO: merge changes...
        }

        this.document_version++;
        pending_queue.add (nc);
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

    private void flush_changes () {
        if (lsp_sync_kind != 1)
            return;
        if (pending_queue.is_empty)
            return;

        var changes = pending_queue;
        pending_queue = new Gee.ArrayList<PendingChange> ();
        if (debounce_id > 0) {
            Source.remove (debounce_id);
            debounce_id = 0;
        }

        // Передаем в менеджер для конвертации и отправки
        var lsp_service = IdeLspService.get_instance ();
        lsp_service.send_did_change.begin (this.source_view.uri, this.document_version, changes);
    }

    private async void flush_changes_async () {
        if (pending_queue.is_empty)return;

        var changes = pending_queue;
        pending_queue = new Gee.ArrayList<PendingChange> ();
        if (debounce_id > 0) {
            Source.remove (debounce_id);
            debounce_id = 0;
        }

        // Передаем в менеджер для конвертации и отправки
        var lsp_service = IdeLspService.get_instance ();
        yield lsp_service.send_did_change (this.source_view.uri, this.document_version, changes);
    }
    
    private async void flush_changes_full_async () {
        this.document_version++;

        // Получаем текст синхронно (он уже актуален, так как мы в Main Loop после паузы)
        string current_text = this.source_view.buffer.text;

        var client = IdeLspService.get_instance ().get_client_for_uri (this.source_view.uri);
        if (client != null) {
            try {
                // Вызываем метод полной синхронизации в новом асинхронном клиенте
                yield client.text_document_did_change (this.source_view.uri, this.document_version, current_text);

                debug ("LSP: Full sync sent for %s (v%d)", this.source_view.uri, this.document_version);
            } catch (Error e) {
                warning ("LSP: Full sync error: %s", e.message);
            }
        }
    }

    public async void sync_changes_async () {
        switch (lsp_sync_kind) {
        case 1:
            yield flush_changes_async ();

            break;
        case 2:
            yield flush_changes_full_async ();

            break;
        }
    }

    // Этот метод вызывается при открытии файла
    public void setup_lsp_sync (LspClient client) {
        this.apply_sync_strategy (client.capabilities, client);
    }

    public void setup_no_lsp_sync () {
        lsp_sync_kind = 0;
        if (change_handler_id > 0)
            this.source_view.disconnect (change_handler_id);

        // Очищаем накопленные дельты (они бесполезны)
        this.pending_queue.clear ();
    }

    private void apply_sync_strategy (ServerCapabilities caps, LspClient client) {
        // Если сервер НЕ умеет в инкремент (Full Sync)
        if (caps.sync_kind != TextDocumentSyncKind.INCREMENTAL) {
            // Отключаем 'before' сигналы
            if (change_handler_id > 0)
                this.source_view.disconnect (change_handler_id);

            // Очищаем накопленные дельты (они бесполезны для Full Sync)
            this.pending_queue.clear ();

            // Переходим на Full Sync (срабатывает ПОСЛЕ вставки текста)
            this.source_view.buffer.changed.connect_after (() => {
                this.start_debounce_full_timer ();
            });

            // ПРИНУДИТЕЛЬНО выравниваем состояние сервера (шлем весь текущий текст)
            client.text_document_did_change.begin (
                this.source_view.uri, this.document_version, this.source_view.buffer.text);
            lsp_sync_kind = 2;
        } else {
            lsp_sync_kind = 1;
            reset_timer ();
        }
    }
    
    private void start_debounce_full_timer () {
        // 1. Сбрасываем старый таймер, если пользователь продолжает печатать
        if (debounce_full_id > 0) {
            Source.remove (debounce_full_id);
        }

        // 2. Устанавливаем задержку (например, 500 мс затишья)
        debounce_full_id = Timeout.add (500, () => {
            this.flush_changes_full_async.begin (); // Запускаем асинхронную отправку
            debounce_full_id = 0;
            return Source.REMOVE;
        });
    }

}