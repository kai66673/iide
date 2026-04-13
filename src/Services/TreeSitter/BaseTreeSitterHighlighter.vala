using Gtk;
using GtkSource;

private struct Iide.TsEdit {
    public uint32 start_byte;
    public uint32 old_end_byte;
    public uint32 new_end_byte;
    public TreeSitter.Point start_point;
    public TreeSitter.Point old_end_point;
    public TreeSitter.Point new_end_point;
}

public abstract class Iide.BaseTreeSitterHighlighter : Object {
    protected View view;
    protected Buffer buffer;
    private TreeSitter.Parser parser;
    private TreeSitter.Tree tree;
    private uint debounce_source = 0;
    private const int DEBOUNCE_DELAY_MS = 50;

    protected abstract unowned TreeSitter.Language language ();

    private Gee.ArrayList<TsEdit?> pending_edits = new Gee.ArrayList<TsEdit?> ();

    protected BaseTreeSitterHighlighter (View view) {
        this.view = view;
        this.buffer = (Buffer) view.get_buffer ();

        parser = new TreeSitter.Parser ();
        parser.set_language (language ());

        buffer.delete_range.connect (on_delete_range);
        buffer.insert_text.connect (on_insert_text);

        buffer.notify["style-scheme"].connect_after (on_style_scheme_changed);

        Idle.add (() => {
            do_reparse ();
            return Source.REMOVE;
        });
    }

    private void on_style_scheme_changed () {
        apply_highlighting_full ();
    }

    private void calculate_text_stats (string text, out uint32 lines, out uint32 last_column) {
        lines = 0;
        last_column = 0;
        int i = 0;
        unichar c;

        while (text.get_next_char (ref i, out c)) {
            if (c == '\n') {
                lines++;
                last_column = 0;
            } else {
                // Tree-sitter ожидает колонки в БАЙТАХ от начала строки
                // Вычисляем длину текущего символа в байтах
                last_column += (uint32) c.to_utf8 (null);
            }
        }
    }

    private void on_insert_text (TextIter iter, string text, int len_bytes) {
        var edit = TsEdit ();

        // Начальные координаты (фиксируем ДО вставки)
        TextIter start_buf;
        buffer.get_start_iter (out start_buf);
        edit.start_byte = (uint32) buffer.get_slice (start_buf, iter, false).length;

        edit.start_point = TreeSitter.Point () {
            row = (uint32) iter.get_line (),
            column = (uint32) iter.get_line_index ()
        };

        // Вставка в Tree-sitter — это замена диапазона нулевой длины на новый текст
        edit.old_end_byte = edit.start_byte;
        edit.old_end_point = edit.start_point;

        // Вычисляем, где окажется конец после вставки
        uint32 lines_added;
        uint32 last_line_bytes;
        calculate_text_stats (text, out lines_added, out last_line_bytes);

        edit.new_end_byte = edit.start_byte + (uint32) text.length;

        edit.new_end_point = TreeSitter.Point () {
            row = edit.start_point.row + lines_added,
            column = lines_added > 0 ? last_line_bytes : edit.start_point.column + last_line_bytes
        };

        pending_edits.add (edit);
        schedule_reparse ();
    }

    private void on_delete_range (TextIter start, TextIter end) {
        var edit = TsEdit ();

        TextIter start_buf;
        buffer.get_start_iter (out start_buf);
        edit.start_byte = (uint32) buffer.get_slice (start_buf, start, false).length;
        edit.old_end_byte = (uint32) buffer.get_slice (start_buf, end, false).length;
        edit.new_end_byte = edit.start_byte;

        edit.start_point = TreeSitter.Point () {
            row = (uint32) start.get_line (),
            column = (uint32) start.get_line_index ()
        };
        edit.old_end_point = TreeSitter.Point () {
            row = (uint32) end.get_line (),
            column = (uint32) end.get_line_index ()
        };
        edit.new_end_point = edit.start_point;

        pending_edits.add (edit);
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
        string full_text = buffer.text;

        if (tree != null) {
            // 1. Инвалидируем узлы в старом дереве
            foreach (var e in pending_edits) {
                var ts_edit = TreeSitter.InputEdit () {
                    start_byte = e.start_byte,
                    old_end_byte = e.old_end_byte,
                    new_end_byte = e.new_end_byte,
                    start_point = e.start_point,
                    old_end_point = e.old_end_point,
                    new_end_point = e.new_end_point
                };
                tree.edit (ts_edit);
            }
        }

        pending_edits.clear ();

        // 2. ВАЖНО: Всегда вызываем парсер.
        // Если tree != null, это будет быстрый инкрементальный парсинг.
        // Если tree == null, это будет полный парсинг с нуля.
        tree = parser.parse_string (tree, full_text.data);

        // 3. Красим результат
        apply_highlighting_full ();
    }

    protected virtual void apply_highlighting_full () {
        if (tree == null)return;

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
