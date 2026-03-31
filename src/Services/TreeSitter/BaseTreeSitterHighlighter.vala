using Gtk;
using GtkSource;

public abstract class Iide.BaseTreeSitterHighlighter : Object {
    protected View view;
    protected Buffer buffer;
    private TreeSitter.Parser parser;
    private TreeSitter.Tree tree;
    private uint debounce_source = 0;
    private const int DEBOUNCE_DELAY_MS = 50;

    protected abstract unowned TreeSitter.Language language();

    protected BaseTreeSitterHighlighter(View view) {
        this.view = view;
        this.buffer = (Buffer) view.get_buffer();

        parser = new TreeSitter.Parser();
        parser.set_language(language());

        buffer.delete_range.connect (on_delete_range);
        buffer.insert_text.connect_after (on_insert_text);

        buffer.notify["style-scheme"].connect_after(on_style_scheme_changed);

        buffer.highlight_syntax = false;
        
        Idle.add (() => {
            do_reparse ();
            return Source.REMOVE;
        });
    }

    private void on_style_scheme_changed() {
        apply_highlighting_full ();
    }

    private void on_delete_range (TextIter start, TextIter end) {
        schedule_reparse ();
    }

    private void on_insert_text (TextIter iter, string text, int length) {
        schedule_reparse ();
    }

    private void schedule_reparse () {
        if (debounce_source != 0) {
            GLib.Source.remove (debounce_source);
        }

        debounce_source = GLib.Timeout.add (DEBOUNCE_DELAY_MS, () => {
            do_reparse ();
            debounce_source = 0;
            return GLib.Source.REMOVE;
        });
    }

    private void do_reparse () {
        string text = buffer.text;
        
        if (tree != null) {
            int edit_start_byte = 0;
            int edit_old_end_byte = text.length;
            int edit_new_end_byte = text.length;

            var edit = TreeSitter.InputEdit () {
                start_byte = (uint32) edit_start_byte,
                old_end_byte = (uint32) edit_old_end_byte,
                new_end_byte = (uint32) edit_new_end_byte,
                start_point = TreeSitter.Point () { row = 0, column = 0 },
                old_end_point = TreeSitter.Point () { row = 0, column = 0 },
                new_end_point = TreeSitter.Point () { row = 0, column = 0 }
            };

            tree.edit (edit);
        }

        tree = parser.parse_string (tree, text.data);
        
        apply_highlighting_full ();
    }

    protected virtual void apply_highlighting_full () {
        if (tree == null) return;

        TextIter start, end;
        buffer.get_bounds (out start, out end);
        buffer.remove_all_tags (start, end);

        traverse_node (tree.root_node (), 0, null);
        
        view.queue_draw ();
    }

    private void traverse_node (TreeSitter.Node node, int depth, TreeSitter.Node? parent_node) {
        highlight_node (node);

        for (uint i = 0; i < node.child_count (); i++) {
            traverse_node (node.child (i), depth + 1, node);
        }
    }

    protected abstract void highlight_node (TreeSitter.Node node);

    protected void highlight_range (TreeSitter.Node node, string style_name) {
        TextIter s_iter, e_iter;
        get_iters_from_ts_node (buffer, node, out s_iter, out e_iter);

        apply_tag_to_range (s_iter, e_iter, style_name);
    }

    protected void apply_tag_to_range (TextIter start, TextIter end, string style_name) {
        var scheme = buffer.style_scheme;
        var style = scheme.get_style (style_name);

        if (style != null) {
            var tag = buffer.tag_table.lookup (style_name);
            if (tag == null) {
                tag = new Gtk.TextTag (style_name);
                buffer.tag_table.add (tag);
            }

            apply_style_to_tag (style, tag);
            buffer.apply_tag (tag, start, end);
        }
    }

    public static void get_iters_from_ts_node (TextBuffer buffer, TreeSitter.Node node,
                                               out TextIter start_iter, out TextIter end_iter) {
        buffer.get_iter_at_line (out start_iter, (int) node.start_point ().row);
        start_iter.set_line_index ((int) node.start_point ().column);
        
        buffer.get_iter_at_line (out end_iter, (int) node.end_point ().row);
        end_iter.set_line_index ((int) node.end_point ().column);
    }

    private void apply_style_to_tag (GtkSource.Style style, Gtk.TextTag tag) {
        if (style.foreground_set) {
            tag.foreground = style.foreground;
        }

        if (style.background_set) {
            tag.background = style.background;
        }

        if (style.bold_set) {
            tag.weight = style.bold ? Pango.Weight.BOLD : Pango.Weight.NORMAL;
        }

        if (style.italic_set) {
            tag.style = style.italic ? Pango.Style.ITALIC : Pango.Style.NORMAL;
        }
    }
}