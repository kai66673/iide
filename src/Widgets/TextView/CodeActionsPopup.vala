/*
*/
public class Iide.CodeActionsPopup : Gtk.Window {
    private Gtk.ListBox list_box;
    private SourceView source_view;
    private LoggerService logger;
    private bool applied = false;

    // Держим результаты живыми на всё время жизни попапа: строки ссылаются на
    // LspCodeActionItem голым указателем (set_data), поэтому без этой ссылки
    // объекты могли быть освобождены сразу после закрытия Idle-колбэка, и
    // применение правки молча не срабатывало. [INDEX]
    private Gee.ArrayList<LspCodeActionResult> results;

    public signal void about_to_close ();

    public CodeActionsPopup (Gtk.Window parent_window, SourceView view, Gee.ArrayList<LspCodeActionResult> results) {
        Object (
            transient_for: parent_window,
            modal: true,         // Закрывает фокус ввода на себя, пока открыто меню [INDEX]
            decorated: false,     // Плоская плашка без системных заголовков и кнопок
            resizable: false,
            title: "Quick Fixes"
        );

        this.source_view = view;
        this.results = results;
        this.logger = view.session != null ? view.session.logger_service : null;
        this.add_css_class ("code-actions-popup");

        this.list_box = new Gtk.ListBox ();
        this.list_box.selection_mode = Gtk.SelectionMode.SINGLE;
        this.list_box.add_css_class ("navigation-sidebar"); // Стиль Adwaita

        foreach (var result in results) {
            var server_name = result.server_name;
            foreach (var action in result.actions) {
                var label = new Gtk.Label ("(" + server_name + ") " + action.title);
                label.halign = Gtk.Align.START;
                label.margin_start = 12;
                label.margin_end = 12;
                label.margin_top = 6;
                label.margin_bottom = 6;

                var row = new Gtk.ListBoxRow ();
                row.set_child (label);
                row.set_data ("action-item", action);

                // Надёжная активация одиночным кликом: в некоторых сборках GTK
                // list_box.row_activated может не срабатывать на один клик,
                // поэтому дублируем срабатывание через GestureClick. [INDEX]
                var gesture = new Gtk.GestureClick ();
                gesture.released.connect ((n, x, y) => {
                    this.apply_action.begin (action);
                });
                row.add_controller (gesture);

                this.list_box.append (row);
            }
        }

        // Обработка выбора исправления (Enter / активация строки)
        this.list_box.row_activated.connect ((row) => {
            Iide.LspCodeActionItem? selected_action = row.get_data ("action-item");
            if (selected_action != null) {
                this.apply_action.begin (selected_action);
            } else {
                this.log_message ("CodeActionsPopup: row_activated fired but action-item data is null.");
            }
        });

        // Контроллер для закрытия по кнопке Esc
        var key_ctrl = new Gtk.EventControllerKey ();
        key_ctrl.key_pressed.connect ((keyval, keycode, state) => {
            if (keyval == Gdk.Key.Escape) {
                this.close_and_focus_editor ();
                return true;
            }
            return false;
        });
        ((Gtk.Widget) this).add_controller (key_ctrl);

        // Закрытие окна, если пользователь кликнул мимо него на экране (Focus Out) [INDEX]
        var focus_ctrl = new Gtk.EventControllerFocus ();
        focus_ctrl.leave.connect (() => {
            // Маленький таймаут, чтобы дать сработать сигналу row_activated до уничтожения окна
            Timeout.add (50, () => {
                this.close_and_focus_editor ();
                return Source.REMOVE;
            });
        });
        ((Gtk.Widget) this).add_controller (focus_ctrl);

        var scrolled = new Gtk.ScrolledWindow ();
        scrolled.set_child (this.list_box);
        scrolled.set_size_request (540, 300);
        scrolled.max_content_height = 400;
        scrolled.propagate_natural_height = true;

        // Кладим настроенный скролл в окно
        this.set_child (scrolled);
    }

    private void log_message (string message) {
        if (this.logger != null) {
            this.logger.info ("LCA-POPUP", message);
        } else {
            stdout.printf ("[LCA-POPUP] %s\n", message);
        }
    }

    private async void apply_action (Iide.LspCodeActionItem action) {
        if (this.applied) {
            this.log_message ("apply_action ignored: already applied (%s)".printf (action.title));
            return;
        }

        this.log_message ("activating action '%s' kind='%s' server='%s' uri='%s'".printf (
            action.title, action.kind, action.server_name, this.source_view.uri
        ));

        var edits = action.changes.get (this.source_view.uri);
        if (edits == null && action.data != null) {
            // Сервер прислал действие без edit — дорезолвливаем через
            // codeAction/resolve (clangd так и делает). [INDEX]
            this.log_message ("action has no inline edits, resolving via codeAction/resolve...");
            edits = yield this.source_view.lsp_document_client.request_code_action_resolve (
                action.server_name, this.source_view.uri, action.data
            );
        }

        if (edits == null) {
            // Если правки так и не нашлись — не проглатываем молча,
            // чтобы такая ситуация была видна в логе. [INDEX]
            this.log_message ("no text edits for uri '%s'. Available: %s".printf (
                this.source_view.uri,
                string.joinv (", ", action.changes.keys.to_array ())
            ));
            this.applied = false;
            this.close_and_focus_editor ();
            return;
        }

        this.applied = true;
        this.log_message ("applying %d edit(s) to buffer.".printf (edits.size));

        // Вызываем ваш атомарный метод применения правок к коду редактора
        this.source_view.apply_lsp_text_edits (edits);

        this.close_and_focus_editor ();
    }

    private void close_and_focus_editor () {
        this.about_to_close ();
        this.destroy (); // Уничтожаем окно из памяти [INDEX]
        this.source_view.grab_focus (); // Гарантированно возвращаем каретку в редактор
    }
}
