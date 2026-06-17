/*
*/

public class Iide.LspServerRow : Adw.ActionRow {
    public LspClient client { get; private set; }
    
    // Текстовые буферы теперь инкапсулированы внутри виджета строки!
    public Gtk.TextBuffer protocol_log_buffer { get; private set; }
    public Gtk.TextBuffer stderr_log_buffer { get; private set; }

    private Gtk.Image status_indicator;
    private Gtk.Button restart_button;

    public LspServerRow (LspClient client) {
        Object (
            title: client.name (),
            subtitle: "Status: Connected",
            activatable: true // Строка кликабельна для вызова логов
        );
        this.client = client;

        // 1. Графический индикатор состояния
        this.status_indicator = new Gtk.Image ();
        this.status_indicator.margin_end = 6;
        this.add_prefix (this.status_indicator);

        // 2. Кнопка ручного горячего перезапуска процесса
        this.restart_button = new Gtk.Button.from_icon_name ("view-refresh-symbolic");
        this.restart_button.add_css_class ("flat");
        this.restart_button.valign = Gtk.Align.CENTER;
        this.restart_button.tooltip_text = "Restart LSP Server";
        this.add_suffix (this.restart_button);

        this.restart_button.clicked.connect (this.on_restart_clicked);

        // Инициализируем локальные UI-буферы
        this.protocol_log_buffer = new Gtk.TextBuffer (null);
        this.stderr_log_buffer = new Gtk.TextBuffer (null);
        this.client.log_message.connect ((type_label, message) => {
            this.append_to_buffer (this.protocol_log_buffer, @"[$type_label]", message);
        });

        this.client.stderr_log_received.connect ((log_line) => {
            this.append_to_buffer (this.stderr_log_buffer, "[STDERR]", log_line);
        });

        // Накатываем стартовый вид
        this.refresh_ui ();
    }

    /**
     * Потокобезопасная вставка строки в выбранный буфер
     */
    private void append_to_buffer (Gtk.TextBuffer buffer, string prefix, string message) {
        string timestamp = new DateTime.now_local ().format ("[%H:%M:%S]");
        string formatted_line = @"$timestamp $prefix $message\n";

        Idle.add (() => {
            Gtk.TextIter end;
            buffer.get_end_iter (out end);
            buffer.insert (ref end, formatted_line, -1);
            return Source.REMOVE;
        });
    }

    /**
     * Синхронизация визуального состояния с конечным автоматом процесса ОС
     */
    public void refresh_ui () {
        if (this.client == null) return;

        this.status_indicator.remove_css_class ("success");
        this.status_indicator.remove_css_class ("warning");
        this.status_indicator.remove_css_class ("error");

        switch (this.client.status) {
            case LspClientStatus.READY:
                this.status_indicator.set_from_icon_name ("emblem-ok-symbolic");
                this.status_indicator.add_css_class ("success");
                this.restart_button.sensitive = true;
                this.subtitle = "Status: Connected & Ready";
                break;

            case LspClientStatus.STARTING:
            case LspClientStatus.INITIALIZING:
                this.status_indicator.set_from_icon_name ("process-working-symbolic");
                this.status_indicator.add_css_class ("warning");
                this.restart_button.sensitive = false;
                this.subtitle = "Status: Handshaking...";
                break;

            case LspClientStatus.FAILED:
                this.status_indicator.set_from_icon_name ("dialog-error-symbolic");
                this.status_indicator.add_css_class ("error");
                this.restart_button.sensitive = true;
                this.subtitle = "Status: Crashed or Missing";
                break;

            case LspClientStatus.STOPPED:
                this.status_indicator.set_from_icon_name ("media-playback-stop-symbolic");
                this.restart_button.sensitive = true;
                this.subtitle = "Status: Stopped";
                break;
        }
    }

    private void on_restart_clicked () {
        this.restart_button.sensitive = false;
        
        // Запускаем асинхронную операцию перезапуска в фоне MainLoop
        this.perform_hot_restart_async.begin ((obj, res) => {
            try {
                this.perform_hot_restart_async.end (res);
            } catch (GLib.Error e) {
                LoggerService.get_instance ().error ("LSP-UI", "Hot restart transaction failed: " + e.message);
            }
        });
    }

    private async void perform_hot_restart_async () throws GLib.Error {
        var prj_manager = ProjectManager.get_instance ();
        string server_name = this.client.name ();
        string? workspace_root = prj_manager.has_open_project () ? 
                                    prj_manager.get_current_project_root ().get_path () : null;

        this.refresh_ui ();
        
        // 1. Двухфазное выключение старого подпроцесса ОС (shutdown -> exit)
        yield this.client.shutdown_and_exit_async ();

        // Очищаем старые консоли перед новым взлетом
        this.protocol_log_buffer.set_text ("", 0);
        this.stderr_log_buffer.set_text ("", 0);

        LoggerService.get_instance ().info ("LSP-UI", @"Respawning process for '$server_name'...");

        // 2. Чистый ленивый повторный запуск
        bool started = yield this.client.start_server_async (workspace_root);
        
        if (started) {
            LoggerService.get_instance ().info ("LSP-UI", @"Server '$server_name' successfully hot-restarted.");
        }
        
        this.refresh_ui ();
    }
}
