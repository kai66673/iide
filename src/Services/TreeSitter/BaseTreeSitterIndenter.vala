/*
 */

public struct Iide.IndentInstruction {
    public string base_indent;
    public int level_delta; // +1 для нового блока, 0 для сохранения уровня
    public int trim_chars; // количество пробелов в конце предыдущей строки
}

public abstract class Iide.BaseTreeSitterIndenter : Object {
    // Каждая реализация (Python, Vala, C) возвращает свой S-Query
    public abstract string get_indent_query_string ();

    protected TreeSitter.Query query;
    protected unowned GtkSource.View view;

    protected BaseTreeSitterIndenter (TreeSitter.Language lang) {
        uint32 error_offset;
        TreeSitter.QueryError error_type;
        var source = get_indent_query_string ();
        this.query = new TreeSitter.Query (lang, source, (uint32) source.length, out error_offset, out error_type);

        if (error_type != TreeSitter.QueryError.None) {
            LoggerService.get_instance ().error ("TS", "TreeSitter Query Error at %u: %s".printf (error_offset, error_type.to_string ()));
        }
    }

    // Вспомогательный метод для получения пробелов в начале строки
    private string get_line_indent_text (Gtk.TextIter line_start) {
        Gtk.TextIter line_end = line_start;
        line_end.forward_to_line_end ();
        string text = line_start.get_buffer ().get_text (line_start, line_end, false);

        string indent = "";
        // Используем индексацию или явный каст, если компилятор капризничает
        for (int i = 0; i < text.length; i++) {
            unichar c = text.get_char (i);
            if (c.isspace ()) {
                indent += c.to_string ();
            } else {
                break;
            }
        }
        return indent;
    }

    public IndentInstruction need_indent (TreeSitter.Tree? tree, Gtk.TextIter iter) {
        IndentInstruction instr = { "", 0, 0 };
        var buffer = iter.get_buffer ();

        // 1. Поиск паразитов (trim_chars)
        Gtk.TextIter ws_check = iter;
        if (ws_check.backward_char ()) { // ушли за \n
            while (ws_check.backward_char () && ws_check.get_char ().isspace () && !ws_check.ends_line ()) {
                instr.trim_chars++;
            }
        }

        // 2. Поиск якоря (ближайшая непустая строка выше)
        Gtk.TextIter anchor = iter;
        bool found_anchor = false;
        while (anchor.backward_line ()) {
            Gtk.TextIter line_end = anchor;
            line_end.forward_to_line_end ();
            if (buffer.get_text (anchor, line_end, false).strip ().length > 0) {
                found_anchor = true;
                break;
            }
        }

        if (found_anchor) {
            instr.base_indent = get_line_indent_text (anchor);

            // 3. Анализ Tree-Sitter
            Gtk.TextIter anchor_end = anchor;
            anchor_end.forward_to_line_end ();
            uint32 end_byte = get_byte_offset_safe (anchor_end);

            if (end_byte > 0) {
                var cursor = new TreeSitter.QueryCursor ();
                // Ищем символ ПЕРЕД концом якорной строки (двоеточие или скобка)
                cursor.set_byte_range (end_byte - 1, end_byte);
                cursor.exec (this.query, tree.root_node ());

                TreeSitter.QueryMatch match;
                while (cursor.next_match (out match)) {
                    for (int i = 0; i < match.capture_count; i++) {
                        unowned TreeSitter.Node node = match.captures[i].node;

                        // Условие 1: Блок начался на этой строке
                        if (node.start_point ().row == (uint32) anchor.get_line ()) {

                            // Условие 2 (ФИКС): Если узел закончился ДО точки разрыва,
                            // значит мы стоим ПОСЛЕ закрывающей скобки. Индент не нужен.
                            if (node.end_byte () <= end_byte) {
                                continue;
                            }

                            instr.level_delta = 1;
                            return instr;
                        }
                    }
                }
            }
        }
        return instr;
    }
}