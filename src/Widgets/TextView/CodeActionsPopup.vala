/*
*/
public class Iide.CodeActionsPopup : Gtk.Window {
    private Gtk.ListBox list_box;
    private SourceView source_view;
    private Gee.ArrayList<Iide.LspCodeActionItem> actions_list;

    public signal void about_to_close ();

    public CodeActionsPopup (Gtk.Window parent_window, SourceView view, Gee.ArrayList<Iide.LspCodeActionItem> actions) {
        Object (
            transient_for: parent_window,
            modal: true,         // Закрывает фокус ввода на себя, пока открыто меню [INDEX]
            decorated: false,     // Плоская плашка без системных заголовков и кнопок
            resizable: false,
            title: "Quick Fixes"
        );

        this.source_view = view;
        this.actions_list = actions;
        this.add_css_class ("code-actions-popup");

        this.list_box = new Gtk.ListBox ();
        this.list_box.selection_mode = Gtk.SelectionMode.SINGLE;
        this.list_box.add_css_class ("navigation-sidebar"); // Стиль Adwaita

        foreach (var action in actions) {
            var label = new Gtk.Label (action.title);
            label.halign = Gtk.Align.START;
            label.margin_start = 12;
            label.margin_end = 12;
            label.margin_top = 6;
            label.margin_bottom = 6;

            var row = new Gtk.ListBoxRow ();
            row.set_child (label);
            row.set_data ("action-item", action);

            this.list_box.append (row);
        }

        // Обработка выбора исправления
        this.list_box.row_activated.connect ((row) => {
            Iide.LspCodeActionItem selected_action = row.get_data ("action-item");
            
            if (selected_action.changes.has_key (this.source_view.uri)) {
                var edits = selected_action.changes.get (this.source_view.uri);
                // Вызываем ваш атомарный метод применения правок к коду редактора
                this.source_view.apply_lsp_text_edits (edits);
            }

            this.close_and_focus_editor ();
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

        this.set_child (scrolled);

        // Кладим настроенный скролл в окно
        this.set_child (scrolled);
    }

    private void close_and_focus_editor () {
        this.about_to_close ();
        this.destroy (); // Уничтожаем окно из памяти [INDEX]
        this.source_view.grab_focus (); // Гарантированно возвращаем каретку в редактор
    }
}
