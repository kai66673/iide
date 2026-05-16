/*
*/

public class Iide.TreeSitterDocument: SourceDocument {
    public BaseTreeSitterHighlighter ts_highlighter;

    public TreeSitterDocument(SourceView source_view, BaseTreeSitterHighlighter ts_highlighter) {
        base(source_view);
        this.ts_highlighter = ts_highlighter;

        source_view.buffer.insert_text.connect ((ref location, text, len) => {
            ts_highlighter.on_insert_text (location,  text, len);
        });

        source_view.buffer.delete_range.connect ((start, end) => {
            ts_highlighter.on_delete_range (start, end);
        });


        this.ts_highlighter.breadcrumbs_changed.connect((crumbs) => {
            this.breadcrumbs_changed(crumbs);
        });
        // Отключаем встроенный highlighter
        ((GtkSource.Buffer) (source_view.buffer)).highlight_syntax = false;

        // Отключаем встроенный indenter если реализован кастомный
        //  source_view.auto_indent = ts_highlighter.ts_indenter == null;
        var indenter = ts_highlighter.create_indenter ();
        if (indenter != null)
            source_view.set_indenter (indenter);
        source_view.auto_indent = true;
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