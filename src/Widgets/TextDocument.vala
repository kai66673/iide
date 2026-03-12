public class Iide.TextView : Gtk.Box {
    private GtkSource.View view;
    public GtkSource.LanguageManager manager;

    public TextView (GLib.File file) {
        Object (orientation: Gtk.Orientation.VERTICAL);

        manager = GtkSource.LanguageManager.get_default ();
        var adw_style_manager = Adw.StyleManager.get_default ();

        var buffer = new GtkSource.Buffer (null);
        var style_manager = GtkSource.StyleSchemeManager.get_default ();
        if (adw_style_manager.color_scheme == Adw.ColorScheme.FORCE_LIGHT) {
            buffer.set_style_scheme (style_manager.get_scheme ("Adwaita"));
        } else {
            buffer.set_style_scheme (style_manager.get_scheme ("Adwaita-dark"));
        }

        // Handle file selection to open documents
        adw_style_manager.notify["color-scheme"].connect (() => {
            if (adw_style_manager.color_scheme == Adw.ColorScheme.FORCE_LIGHT) {
                buffer.set_style_scheme (style_manager.get_scheme ("Adwaita"));
            } else {
                buffer.set_style_scheme (style_manager.get_scheme ("Adwaita-dark"));
            }
        });

        view = new GtkSource.View.with_buffer (buffer);

        uint8[] contents;
        file.load_contents (null, out contents, null);
        buffer.text = (string) contents;

        change_syntax_highlight_from_file (file);

        view.show_line_numbers = true;
        view.highlight_current_line = true;
        view.auto_indent = true;
        view.indent_on_tab = true;

        var scroll = new Gtk.ScrolledWindow ();
        scroll.vexpand = true;
        scroll.set_child (view);
        append (scroll);
    }

    // lang can be null, in the case of *No highlight style* aka Normal text
    public GtkSource.Language? language {
        set {
            ((GtkSource.Buffer) view.buffer).language = value;
        }
        get {
            return ((GtkSource.Buffer) view.buffer).language;
        }
    }

    public void change_syntax_highlight_from_file (GLib.File file) {
        try {
            var info = file.query_info ("standard::*", FileQueryInfoFlags.NONE, null);
            var mime_type = ContentType.get_mime_type (info.get_attribute_as_string (FileAttribute.STANDARD_CONTENT_TYPE));
            language = manager.guess_language (file.get_path (), mime_type);
        } catch (Error e) {
            critical (e.message);
        }

        // Fake file type detection
        // "Not all files are equal"
        if (file.get_basename () == "CMakeLists.txt") {
            language = manager.get_language ("cmake");
        }
    }
}
