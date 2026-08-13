/*
*/

public class Iide.RenameFileDialog : Gtk.Window {
    // Сигнал с новым именем файла (basename) при подтверждении
    public signal void confirmed (string new_name);

    private Gtk.Entry entry;
    private Gtk.Button apply_button;
    private string old_basename;

    public RenameFileDialog (Gtk.Window parent_window, GLib.File file) {
        Object (
            transient_for: parent_window,
            modal: true,         // Закрывает фокус ввода на себя, пока открыто окно [INDEX]
            decorated: false,     // Плоская плашка без системных заголовков и кнопок
            resizable: false,
            title: "Rename File"
        );

        this.add_css_class ("code-actions-popup");

        this.old_basename = file.get_basename () ?? "";

        var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 12) {
            margin_top = 12,
            margin_bottom = 12,
            margin_start = 12,
            margin_end = 12
        };

        var title_label = new Gtk.Label (_("Rename File")) {
            halign = Gtk.Align.START
        };
        title_label.add_css_class ("heading");
        box.append (title_label);

        var path_label = new Gtk.Label (file.get_path () ?? file.get_uri ()) {
            halign = Gtk.Align.START,
            ellipsize = Pango.EllipsizeMode.MIDDLE,
            max_width_chars = 60
        };
        path_label.add_css_class ("dim-label");
        path_label.add_css_class ("caption");
        box.append (path_label);

        this.entry = new Gtk.Entry () {
            hexpand = true
        };
        this.entry.set_text (this.old_basename);

        // Сразу выделяем имя без расширения, чтобы пользователь мог
        // набрать новое имя, не стирая расширение вручную
        int dot = this.old_basename.last_index_of_char ('.');
        int sel_end = dot > 0 ? dot : this.old_basename.length;
        this.entry.select_region (0, sel_end);
        box.append (this.entry);

        var button_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6) {
            halign = Gtk.Align.END,
            margin_top = 6
        };

        var cancel_button = new Gtk.Button.with_label (_("Cancel"));
        cancel_button.clicked.connect (() => this.close_dialog ());
        button_box.append (cancel_button);

        this.apply_button = new Gtk.Button.with_label (_("Rename"));
        this.apply_button.add_css_class ("suggested-action");
        this.apply_button.clicked.connect (() => this.finish ());
        button_box.append (this.apply_button);

        box.append (button_box);
        this.set_child (box);

        // Валидация: пустое имя или без изменений — кнопка неактивна
        this.entry.notify["text"].connect (() => this.update_sensitivity ());

        // Enter в поле ввода = подтверждение
        this.entry.activate.connect (() => this.finish ());

        // Esc закрывает диалог
        var key_ctrl = new Gtk.EventControllerKey ();
        key_ctrl.key_pressed.connect ((keyval, keycode, state) => {
            if (keyval == Gdk.Key.Escape) {
                this.close_dialog ();
                return true;
            }
            return false;
        });
        ((Gtk.Widget) this).add_controller (key_ctrl);

        this.update_sensitivity ();
    }

    private void update_sensitivity () {
        string text = this.entry.text.strip ();
        this.apply_button.sensitive = text.length > 0 && text != this.old_basename;
    }

    private void finish () {
        string new_name = this.entry.text.strip ();
        if (new_name.length == 0 || new_name == this.old_basename)
            return;

        this.confirmed (new_name);
        this.close_dialog ();
    }

    private void close_dialog () {
        this.destroy ();
    }
}
