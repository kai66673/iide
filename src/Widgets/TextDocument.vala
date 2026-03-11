public class Iide.TextView : Gtk.Box {
    public TextView () {
        Object (orientation: Gtk.Orientation.VERTICAL);

        var buffer = new GtkSource.Buffer (null);

        var view = new GtkSource.View.with_buffer (buffer);
        view.show_line_numbers = true;
        view.highlight_current_line = true;
        view.auto_indent = true;
        view.indent_on_tab = true;

        var scroll = new Gtk.ScrolledWindow ();
        scroll.vexpand = true;
        scroll.set_child (view);
        append (scroll);
    }
}
