/*
*/
public class Iide.DiagnosticsBar : Gtk.Box {
    private class _Statistics {
        private struct IntPair {
            public int errors;
            public int warnings;

            public IntPair(int errors, int warnings) {
                this.errors = errors;
                this.warnings = warnings;
            }
        }

        private Gee.HashMap<string, IntPair?> _data = new Gee.HashMap<string, IntPair?> ();

        public void update (string server_name, int errors, int warnings, out int total_errors, out int total_warnings) {
            _data.set (server_name, IntPair(errors, warnings));

            total_errors = 0;
            total_warnings = 0;
            foreach (var item in _data.values) {
                total_errors += item.errors;
                total_warnings += item.warnings;
            }
        }
    }

    private SourceView source_view;
    private Gtk.Label error_label;
    private Gtk.Label warn_label;
    private Iide.DiagnosticsPopover diag_popover = null;

    private _Statistics statistics;

    public DiagnosticsBar (SourceView source_view) {
        Object (
            orientation: Gtk.Orientation.HORIZONTAL,
            spacing: 8
        );

        this.source_view = source_view;
        statistics = new _Statistics ();

        // Ошибки (Красный)
        error_label = new Gtk.Label ("0");
        error_label.add_css_class ("error-label"); // Настроим цвет в CSS

        // Предупреждения (Желтый)
        warn_label = new Gtk.Label ("0");
        warn_label.add_css_class ("warning-label");

        var icon_provider = SymbIconProvider.get_instance ();

        this.append (icon_provider.image (IconID.COD_ERROR));
        this.append (error_label);
        this.append (icon_provider.image (IconID.COD_WARNING));
        this.append (warn_label);
        
        this.init_diagnostics_interaction ();
        this.add_css_class ("diagnostic-box");

        this.hide ();
    }

    public void update_diagnostics (string server_name, int errors, int warnings) {
        int total_errors;
        int total_warnings;
        statistics.update (server_name, errors, warnings, out total_errors, out total_warnings);

        if (total_errors == 0 && total_warnings == 0) {
            this.hide ();
            return;
        }

        this.show ();
        this.error_label.label = total_errors.to_string ();
        this.warn_label.label = total_warnings.to_string ();
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
        this.add_controller (click_gesture);

        // (Опционально) Добавим визуальный отклик: смена курсора при наведении
        this.set_cursor (new Gdk.Cursor.from_name ("pointer", null));

        // --- 2. Контроллер наведения (Hover) ---
        var motion_controller = new Gtk.EventControllerMotion ();

        // Когда мышь заходит в область
        motion_controller.enter.connect ((x, y) => {
            this.add_css_class ("hover");
            // Меняем курсор на "руку"
            this.set_cursor (new Gdk.Cursor.from_name ("pointer", null));
        });

        // Когда мышь покидает область
        motion_controller.leave.connect (() => {
            this.remove_css_class ("hover");
            // Возвращаем обычный курсор
            this.set_cursor (null);
        });

        this.add_controller (motion_controller);
    }

    private void show_diagnostics_popup () {
        if (this.diag_popover == null) {
            // Создаем попап, привязывая его к diagnostic_box
            this.diag_popover = new Iide.DiagnosticsPopover (this, this.source_view);
        }

        // Обновляем список ошибок из буфера перед показом
        this.diag_popover.refresh ();
        this.diag_popover.popup ();
    }
}