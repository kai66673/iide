/*
*/

public class Iide.SourceDocument: GLib.Object {
    public signal void document_changed(PendingChange new_change);
    public signal void breadcrumbs_changed (Gee.List<SourceNodeItem?> crumbs);

    protected virtual bool handle_key_pressed(uint keyval, uint keycode, Gdk.ModifierType modifiers) { return false; }
    protected virtual void handle_insert_text (Gtk.TextIter iter, string text, int len_bytes) {}
    protected virtual void handle_delete_range (Gtk.TextIter start, Gtk.TextIter end) {}

    public virtual void expand_selection() {}
    public virtual void shrink_selection() {}
    public virtual Gee.List<SourceNodeItem?> get_full_outline () {
        return new Gee.ArrayList<SourceNodeItem?> ();
    }

    public SourceDocument(SourceView source_view) {
        Object();

        source_view.buffer.insert_text.connect ((ref location, text, len) => {
            var change = new PendingChange (text, location);
            this.document_changed (change);
            handle_insert_text(location, text, len);
        });

        source_view.buffer.delete_range.connect ((start, end) => {
            var change = new PendingChange ("", start, end);
            this.document_changed (change);
            handle_delete_range (start, end);
        });

        var key_controller = new Gtk.EventControllerKey ();
        key_controller.key_pressed.connect (on_key_pressed);
        source_view.add_controller (key_controller);

        // Включаем встроенный highlighter
        ((GtkSource.Buffer) (source_view.buffer)).highlight_syntax = true;

        // Включаем встроенный indenter
        source_view.auto_indent = true;
    }

    private bool on_key_pressed (Gtk.EventControllerKey controller, uint keyval, uint keycode, Gdk.ModifierType modifiers) {
        return handle_key_pressed (keyval, keycode, modifiers);
    }
}