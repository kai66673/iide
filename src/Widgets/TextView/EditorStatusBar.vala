public class Iide.EditorStatusBar : Gtk.Box {
    private SourceView source_view;
    private Gtk.Label pos_label;
    private Gtk.Label mode_label;

    private Gtk.Label error_label;
    private Gtk.Label warn_label;
    private Gtk.Box diagnostic_box;

    private BreadcrumbsBar new_breadcrumps;

    public signal void breadcrumb_clicked (uint line, uint column);

    private Iide.DiagnosticsPopover diag_popover = null;

    public EditorStatusBar (SourceView source_view) {
        Object (orientation: Gtk.Orientation.HORIZONTAL, spacing: 12);
        this.source_view = source_view;
        this.add_css_class ("editor-status-bar");

        // Левая часть: Breadcrumbs
        new_breadcrumps = new BreadcrumbsBar ();
        this.append (new_breadcrumps);
        new_breadcrumps.update_file_path (GLib.File.new_for_uri (source_view.uri),
                                          GLib.File.new_for_path (ProjectManager.get_instance ().get_workspace_root_path ()));

        new_breadcrumps.breadcrumb_clicked.connect ((line, column) => { breadcrumb_clicked (line, column); });

        // spacer
        var spacer_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 2);
        spacer_box.hexpand = true;
        this.append (spacer_box);

        // Правая часть: Статистика
        var info_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);

        mode_label = new Gtk.Label ("INS");
        mode_label.add_css_class ("dim-label");
        mode_label.height_request = 24;

        pos_label = new Gtk.Label ("1:1");

        info_box.append (mode_label);
        info_box.append (pos_label);
        this.append (info_box);

        diagnostic_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);

        // Ошибки (Красный)
        error_label = new Gtk.Label ("0");
        error_label.add_css_class ("error-label"); // Настроим цвет в CSS

        // Предупреждения (Желтый)
        warn_label = new Gtk.Label ("0");
        warn_label.add_css_class ("warning-label");

        diagnostic_box.append (new Gtk.Image.from_icon_name ("dialog-error-symbolic"));
        diagnostic_box.append (error_label);
        diagnostic_box.append (new Gtk.Image.from_icon_name ("dialog-warning-symbolic"));
        diagnostic_box.append (warn_label);

        // Добавляем в инфо-бокс перед позицией курсора
        info_box.prepend (diagnostic_box);
        diagnostic_box.hide (); // Скрываем, если ошибок нет

        init_diagnostics_interaction ();
        this.diagnostic_box.add_css_class ("diagnostic-box");
    }

    private void init_diagnostics_interaction () {
        // Создаем контроллер жеста клика
        var click_gesture = new Gtk.GestureClick ();

        // Подключаемся к событию нажатия (pressed)
        click_gesture.pressed.connect ((n_press, x, y) => {
            // Мы вызываем метод, который создаст или обновит Popover
            show_diagnostics_popup ();
        });

        // Привязываем жест к вашему боксу
        this.diagnostic_box.add_controller (click_gesture);

        // (Опционально) Добавим визуальный отклик: смена курсора при наведении
        this.diagnostic_box.set_cursor (new Gdk.Cursor.from_name ("pointer", null));

        // --- 2. Контроллер наведения (Hover) ---
        var motion_controller = new Gtk.EventControllerMotion ();

        // Когда мышь заходит в область
        motion_controller.enter.connect ((x, y) => {
            this.diagnostic_box.add_css_class ("hover");
            // Меняем курсор на "руку"
            this.diagnostic_box.set_cursor (new Gdk.Cursor.from_name ("pointer", null));
        });

        // Когда мышь покидает область
        motion_controller.leave.connect (() => {
            this.diagnostic_box.remove_css_class ("hover");
            // Возвращаем обычный курсор
            this.diagnostic_box.set_cursor (null);
        });

        this.diagnostic_box.add_controller (motion_controller);
    }

    private void show_diagnostics_popup () {
        if (this.diag_popover == null) {
            // Создаем попап, привязывая его к diagnostic_box
            this.diag_popover = new Iide.DiagnosticsPopover (this.diagnostic_box, this.source_view);
        }

        // Обновляем список ошибок из буфера перед показом
        this.diag_popover.refresh ();
        this.diag_popover.popup ();
    }

    public void update_diagnostics (int errors, int warnings, int infos) {
        if (errors == 0 && warnings == 0 && infos == 0) {
            diagnostic_box.hide ();
            return;
        }

        diagnostic_box.show ();
        error_label.label = errors.to_string ();
        warn_label.label = (warnings + infos).to_string ();
    }

    public void update_breadcrumbs (Gee.List<BreadcrumbItem?> crumbs) {
        new_breadcrumps.update_breadcrumbs (crumbs);
    }

    public void update_position (int line, int col, int selection_len = 0) {
        if (selection_len > 0) {
            pos_label.label = "%d:%d (%d selected)".printf (line + 1, col + 1, selection_len);
        } else {
            pos_label.label = "%d:%d".printf (line + 1, col + 1);
        }
    }

    public void update_mode (bool overwrite) {
        mode_label.label = overwrite ? "OVR" : "INS";
    }
}