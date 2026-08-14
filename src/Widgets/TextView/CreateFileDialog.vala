/*
 * CreateFileDialog.vala
 *
 * Диалог ввода имени нового файла или директории.
 * Ведёт себя как RenameFileDialog: плоская плашка, Enter подтверждает,
 * Esc закрывает, кнопка неактивна при невалидном имени.
 */

public class Iide.CreateFileDialog : Gtk.Window {
    // Сигнал с именем нового файла/директории (basename) при подтверждении
    public signal void confirmed (string name);

    private Gtk.Entry entry;
    private Gtk.Button apply_button;
    private bool is_directory;

    public CreateFileDialog (Gtk.Window parent_window, GLib.File parent_dir, bool is_directory) {
        string title = is_directory ? _("New Directory") : _("New File");

        Object (
            transient_for: parent_window,
            modal: true,         // Закрывает фокус ввода на себя, пока открыто окно [INDEX]
            decorated: false,     // Плоская плашка без системных заголовков и кнопок
            resizable: false,
            title: title
        );

        this.is_directory = is_directory;
        this.add_css_class ("code-actions-popup");

        var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 12) {
            margin_top = 12,
            margin_bottom = 12,
            margin_start = 12,
            margin_end = 12
        };

        var title_label = new Gtk.Label (title) {
            halign = Gtk.Align.START
        };
        title_label.add_css_class ("heading");
        box.append (title_label);

        var path_label = new Gtk.Label (parent_dir.get_path () ?? parent_dir.get_uri ()) {
            halign = Gtk.Align.START,
            ellipsize = Pango.EllipsizeMode.MIDDLE,
            max_width_chars = 60
        };
        path_label.add_css_class ("dim-label");
        path_label.add_css_class ("caption");
        box.append (path_label);

        this.entry = new Gtk.Entry () {
            hexpand = true,
            placeholder_text = is_directory ? _("untitled folder") : _("untitled")
        };
        box.append (this.entry);

        var button_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6) {
            halign = Gtk.Align.END,
            margin_top = 6
        };

        var cancel_button = new Gtk.Button.with_label (_("Cancel"));
        cancel_button.clicked.connect (() => this.close_dialog ());
        button_box.append (cancel_button);

        this.apply_button = new Gtk.Button.with_label (_("Create"));
        this.apply_button.add_css_class ("suggested-action");
        this.apply_button.clicked.connect (() => this.finish ());
        button_box.append (this.apply_button);

        box.append (button_box);
        this.set_child (box);

        // Валидация: пустое имя или разделитель пути — кнопка неактивна
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

        this.entry.grab_focus ();
        this.update_sensitivity ();
    }

    private bool is_valid_name (string name) {
        if (name.length == 0)
            return false;
        if (name == "." || name == "..")
            return false;
        if (name.contains ("/"))
            return false;
        return true;
    }

    private void update_sensitivity () {
        this.apply_button.sensitive = this.is_valid_name (this.entry.text.strip ());
    }

    private void finish () {
        string name = this.entry.text.strip ();
        if (!this.is_valid_name (name))
            return;

        this.confirmed (name);
        this.close_dialog ();
    }

    private void close_dialog () {
        this.destroy ();
    }
}
