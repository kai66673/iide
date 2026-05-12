/*
*/

public class Iide.TreeSitterDocument: SourceDocument {
    public BaseTreeSitterHighlighter ts_highlighter;

    public TreeSitterDocument(SourceView source_view, BaseTreeSitterHighlighter ts_highlighter) {
        base(source_view);
        this.ts_highlighter = ts_highlighter;

        this.ts_highlighter.breadcrumbs_changed.connect((crumbs) => {
            this.breadcrumbs_changed(crumbs);
        });
        // Отключаем встроенный highlighter
        ((GtkSource.Buffer) (source_view.buffer)).highlight_syntax = false;

        // Отключаем встроенный indenter если реализован кастомный
        source_view.auto_indent = ts_highlighter.ts_indenter == null;
    }

    protected override void handle_insert_text (Gtk.TextIter iter, string text, int len_bytes) {
        ts_highlighter.on_insert_text (iter,  text, len_bytes);
    }
    protected override void handle_delete_range (Gtk.TextIter start, Gtk.TextIter end) {
        ts_highlighter.on_delete_range (start, end);
    }

    protected override bool handle_key_pressed(uint keyval, uint keycode, Gdk.ModifierType modifiers) { 
        return ts_highlighter.handle_key_pressed (keyval, keycode, modifiers); 
    }

    public override void expand_selection() {
        ts_highlighter.expand_selection ();
    }

    public override void shrink_selection() {
        ts_highlighter.shrink_selection ();
    }

    public override Gee.List<SourceNodeItem?> get_full_outline () {
        return ts_highlighter.get_full_outline ();
    }
}