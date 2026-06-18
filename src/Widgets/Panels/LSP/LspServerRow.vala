/*
*/

public class Iide.LspServerRow : Adw.ActionRow {
    public LspClient client { get; private set; }
    
    // Текстовые буферы теперь инкапсулированы внутри виджета строки!
    public Gtk.TextBuffer protocol_log_buffer { get; private set; }
    public Gtk.TextBuffer stderr_log_buffer { get; private set; }

    private Gtk.Image status_indicator;
    private Gtk.Button start_button;
    private Gtk.Button stop_button;

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

        // 1. Кнопка ЗАПУСКА
        this.start_button = new Gtk.Button.from_icon_name ("media-playback-start-symbolic");
        this.start_button.add_css_class ("flat");
        this.start_button.valign = Gtk.Align.CENTER;
        this.start_button.tooltip_text = "Start LSP Server";
        this.add_suffix (this.start_button);

        // 2. Кнопка ОСТАНОВКИ
        this.stop_button = new Gtk.Button.from_icon_name ("media-playback-stop-symbolic");
        this.stop_button.add_css_class ("flat");
        this.stop_button.valign = Gtk.Align.CENTER;
        this.stop_button.tooltip_text = "Stop LSP Server";
        this.add_suffix (this.stop_button);

        // Назначаем независимые обработчики кликов
        this.start_button.clicked.connect (this.on_start_clicked);
        this.stop_button.clicked.connect (this.on_stop_clicked);

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
            case LspClientStatus.STOPPED:
                this.status_indicator.set_from_icon_name ("media-playback-stop-symbolic");
                this.start_button.sensitive = true;
                this.stop_button.sensitive = false;
                this.subtitle = "Status: Inactive";
                break;

            case LspClientStatus.READY:
                this.status_indicator.set_from_icon_name ("emblem-ok-symbolic");
                this.status_indicator.add_css_class ("success");
                this.start_button.sensitive = false; // Уже запущен
                this.stop_button.sensitive = true;   // Можно остановить
                this.subtitle = "Status: Ready";
                break;

            case LspClientStatus.STARTING:
            case LspClientStatus.INITIALIZING:
                this.status_indicator.set_from_icon_name ("process-working-symbolic");
                this.status_indicator.add_css_class ("warning");
                this.start_button.sensitive = false; // Блокируем во время транзакции
                this.stop_button.sensitive = false;
                this.subtitle = "Status: Handshaking...";
                break;

            case LspClientStatus.FAILED:
                this.status_indicator.set_from_icon_name ("dialog-error-symbolic");
                this.status_indicator.add_css_class ("error");
                this.start_button.sensitive = true;  // Позволяем перезапустить упавший !?
                this.stop_button.sensitive = false;
                this.subtitle = "Status: Crashed or Missing";
                break;

            case LspClientStatus.ABORTED:
                this.status_indicator.set_from_icon_name ("dialog-error-symbolic");
                this.status_indicator.add_css_class ("error");
                this.start_button.sensitive = true;  // Можно разбудить руками
                this.stop_button.sensitive = false;  // Уже мертв
                this.subtitle = "Status: Aborted";
                break;
        }
    }

    /**
        * МЕТОД 1: МАНУАЛЬНАЯ ПРИНУДИТЕЛЬНАЯ ОСТАНОВКА (Кнопка Стоп)
        */
    private void on_stop_clicked () {
        this.start_button.sensitive = false;
        this.stop_button.sensitive = false;

        this.execute_stop_async.begin ((obj, res) => {
            try {
                this.execute_stop_async.end (res);
            } catch (GLib.Error e) {
                LoggerService.get_instance ().error ("LSP-UI", "Stop transaction failed: " + e.message);
                this.refresh_ui ();
            }
        });
    }

    private async void execute_stop_async () throws GLib.Error {
        LoggerService.get_instance ().info ("LSP-UI", @"[Manual Stop] Shutting down process: '$(this.client.name())'...");
        
        // Тушим потоки ввода-вывода
        yield this.client.shutdown_and_exit_async ();

        // ЖЕСТКО ВЗВОДИМ СТАТУС ABORTED, БЛОКИРУЯ АВТОМАТИЧЕСКИЙ RESPOND В СEРВИСE
        this.client.status = LspClientStatus.ABORTED;

        // Очищаем текстовые поля логов
        this.protocol_log_buffer.set_text ("", 0);
        this.stderr_log_buffer.set_text ("", 0);

        this.refresh_ui ();
    }

    /**
     * МЕТОД 2: МАНУАЛЬНЫЙ ЦЕЛЕНАПРАВЛЕННЫЙ ЗАПУСК (Кнопка Старт)
     */
    private void on_start_clicked () {
        this.start_button.sensitive = false;
        this.stop_button.sensitive = false;

        this.execute_start_async.begin ((obj, res) => {
            try {
                this.execute_start_async.end (res);
            } catch (GLib.Error e) {
                LoggerService.get_instance ().error ("LSP-UI", "Start transaction failed: " + e.message);
                this.refresh_ui ();
            }
        });
    }

    private async void execute_start_async () throws GLib.Error {
        var prj_manager = ProjectManager.get_instance ();
        string? workspace_root = prj_manager.has_open_project () ? 
                                    prj_manager.get_current_project_root ().get_path () : null;

        LoggerService.get_instance ().info ("LSP-UI", @"[Manual Start] Spawning process for '$(this.client.name())'...");

        // Принудительно выбиваем сервер из статуса ABORTED/FAILED, переводя в STOPPED, чтобы старт_async пропустил его
        this.client.status = LspClientStatus.STOPPED;

        bool started = yield this.client.start_server_async (workspace_root);
        
        if (!started) {
            this.client.status = LspClientStatus.FAILED;
        }

        this.refresh_ui ();
    }
}
