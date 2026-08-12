/*
*/

public class Iide.RenamePreviewDialog : Gtk.Window {
    private SourceView source_view;

    // Выбранные (отмеченные галочкой) файлы и их правки
    public signal void confirmed (Gee.HashMap<string, Gee.ArrayList<LspTextEdit>> selected_edits);

    private Gee.HashMap<string, Gtk.CheckButton> check_buttons =
        new Gee.HashMap<string, Gtk.CheckButton> ();
    private Gtk.Button apply_button;

    public RenamePreviewDialog (Gtk.Window parent_window, SourceView view, Gee.HashMap<string, Gee.ArrayList<LspTextEdit>> edits_map) {
        Object (
            transient_for: parent_window,
            modal: true,         // Закрывает фокус ввода на себя, пока открыто окно [INDEX]
            decorated: false,     // Плоская плашка без системных заголовков и кнопок
            resizable: false,
            title: "Rename Preview"
        );

        this.source_view = view;
        this.add_css_class ("code-actions-popup");

        var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 12) {
            margin_top = 12,
            margin_bottom = 12,
            margin_start = 12,
            margin_end = 12
        };

        var title_label = new Gtk.Label (ngettext (
            "Rename affects 1 file. Confirm changes?",
            "Rename affects %u files. Confirm changes?",
            edits_map.size
        ).printf (edits_map.size)) {
            halign = Gtk.Align.START
        };
        title_label.add_css_class ("heading");
        box.append (title_label);

        // Кнопки быстрого выбора всех / ни одного файла
        var select_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6) {
            halign = Gtk.Align.START
        };

        var select_all_button = new Gtk.Button.with_label (_("Select all"));
        select_all_button.add_css_class ("flat");
        select_all_button.clicked.connect (() => {
            foreach (var check in this.check_buttons.values) {
                check.active = true;
            }
        });
        select_box.append (select_all_button);

        var select_none_button = new Gtk.Button.with_label (_("Select none"));
        select_none_button.add_css_class ("flat");
        select_none_button.clicked.connect (() => {
            foreach (var check in this.check_buttons.values) {
                check.active = false;
            }
        });
        select_box.append (select_none_button);

        box.append (select_box);

        // Список файлов с чекбоксами и количеством правок в каждом
        var list_box = new Gtk.ListBox ();
        list_box.selection_mode = Gtk.SelectionMode.NONE;
        list_box.add_css_class ("navigation-sidebar"); // Стиль Adwaita

        foreach (var entry in edits_map.entries) {
            var file_uri = entry.key;
            var edits = entry.value;

            // Чекбокс целиком занимает строку: клик по любой части строки
            // переключает галочку. По умолчанию все правки включены.
            var check = new Gtk.CheckButton () {
                active = true
            };

            var details_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 2) {
                margin_start = 8,
                margin_end = 12,
                margin_top = 6,
                margin_bottom = 6
            };

            string file_path = GLib.File.new_for_uri (file_uri).get_path () ?? file_uri;
            var path_label = new Gtk.Label (file_path) {
                halign = Gtk.Align.START,
                ellipsize = Pango.EllipsizeMode.MIDDLE,
                max_width_chars = 70
            };
            details_box.append (path_label);

            var count_label = new Gtk.Label (ngettext (
                "%u edit",
                "%u edits",
                edits.size
            ).printf (edits.size)) {
                halign = Gtk.Align.START
            };
            count_label.add_css_class ("dim-label");
            count_label.add_css_class ("caption");
            details_box.append (count_label);

            check.set_child (details_box);
            this.check_buttons.set (file_uri, check);
            check.toggled.connect (() => this.update_apply_sensitivity ());

            var row = new Gtk.ListBoxRow ();
            row.set_child (check);
            list_box.append (row);
        }

        var scrolled = new Gtk.ScrolledWindow ();
        scrolled.set_child (list_box);
        scrolled.set_size_request (520, -1);
        scrolled.max_content_height = 320;
        scrolled.propagate_natural_height = true;
        box.append (scrolled);

        // Кнопки Отмена / Применить
        var button_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6) {
            halign = Gtk.Align.END,
            margin_top = 6
        };

        var cancel_button = new Gtk.Button.with_label (_("Cancel"));
        cancel_button.clicked.connect (() => this.close_and_focus_editor ());
        button_box.append (cancel_button);

        this.apply_button = new Gtk.Button.with_label (_("Apply"));
        this.apply_button.add_css_class ("suggested-action");
        this.apply_button.clicked.connect (() => {
            var selected = new Gee.HashMap<string, Gee.ArrayList<LspTextEdit>> ();
            foreach (var entry in this.check_buttons.entries) {
                if (entry.value.active) {
                    selected.set (entry.key, edits_map.get (entry.key));
                }
            }
            this.confirmed (selected);
            this.close_and_focus_editor ();
        });
        button_box.append (this.apply_button);

        box.append (button_box);
        this.set_child (box);

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

        this.update_apply_sensitivity ();
    }

    private void update_apply_sensitivity () {
        bool any_selected = false;
        foreach (var check in this.check_buttons.values) {
            if (check.active) {
                any_selected = true;
                break;
            }
        }
        this.apply_button.sensitive = any_selected;
    }

    private void close_and_focus_editor () {
        this.destroy (); // Уничтожаем окно из памяти [INDEX]
        this.source_view.grab_focus (); // Гарантированно возвращаем каретку в редактор
    }
}
