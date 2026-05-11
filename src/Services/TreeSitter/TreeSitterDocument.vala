/*
*/

public class Iide.TreeSitterDocument: SourceDocument {
    public BaseTreeSitterHighlighter ts_highlighter;

    public TreeSitterDocument(SourceView source_view, BaseTreeSitterHighlighter ts_highlighter) {
        base(source_view);
        this.ts_highlighter = ts_highlighter;

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

}