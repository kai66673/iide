/*
*/
public class Iide.PythonIndenter: GtkSource.Indenter, Object {
    private BaseTreeSitterHighlighter ts_highlighter;
    protected TreeSitter.Query query;
    public bool is_valid = true;
    private const string source = """
        ; Узлы, которые открывают новый уровень отступа (class_definition) @indent.begin
        (function_definition) @indent.begin
        (if_statement) @indent.begin
        (elif_clause) @indent.begin
        (else_clause) @indent.begin
        (for_statement) @indent.begin
        (while_statement) @indent.begin
        (with_statement) @indent.begin
        (try_statement) @indent.begin
        (except_clause) @indent.begin
        (finally_clause) @indent.begin
        (parenthesized_expression) @indent.begin
        (list) @indent.begin
        (dictionary) @indent.begin
        (argument_list) @indent.begin
        (parameters) @indent.begin
    """;

    public PythonIndenter (BaseTreeSitterHighlighter ts_highlighter, TreeSitter.Language lang) {
        Object ();
        this.ts_highlighter = ts_highlighter;

        uint32 error_offset;
        TreeSitter.QueryError error_type;
        this.query = new TreeSitter.Query (lang, source, (uint32) source.length, out error_offset, out error_type);

        if (error_type != TreeSitter.QueryError.None) {
            LoggerService.get_instance ().error ("TS", "TreeSitter Query Error at %u: %s".printf (error_offset, error_type.to_string ()));
            this.is_valid = false;
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

    public void indent (GtkSource.View view, ref Gtk.TextIter iter) {
        if (!is_valid)
            return;

        if (ts_highlighter.get_tree () == null)
            return;

        ts_highlighter. flush_changes();

        // 1. Поиск якоря (ближайшая непустая строка выше)
        Gtk.TextIter anchor = iter;
        bool found_anchor = false;
        while (anchor.backward_line ()) {
            Gtk.TextIter line_end = anchor;
            line_end.forward_to_line_end ();
            if (view.buffer.get_text (anchor, line_end, false).strip ().length > 0) {
                found_anchor = true;
                break;
            }
        }
        if (!found_anchor)
            return;

        // 2. Получаем базовое смещение с якорной строки
        var base_indent = get_line_indent_text (anchor);

        // 3. Анализ Tree-Sitter
        Gtk.TextIter anchor_end = anchor;
        anchor_end.forward_to_line_end ();
        uint32 end_byte = get_byte_offset_safe (anchor_end);

        if (end_byte > 0) {
            var cursor = new TreeSitter.QueryCursor ();
            // Ищем символ ПЕРЕД концом якорной строки (двоеточие или скобка)
            cursor.set_byte_range (end_byte - 1, end_byte);
            cursor.exec (this.query, ts_highlighter.get_tree ().root_node ());

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

                        base_indent += "    ";
                        break;
                    }
                }
            }
        }

        // 4. Выполняем сдвиг в одной транзакции
        view.buffer.begin_user_action ();

        view.buffer.insert (ref iter, base_indent, base_indent.length);
        
        // Remove space symbols from current position...
        Gtk.TextIter line_start = iter;
        Gtk.TextIter line_end = line_start;
        while (line_end.get_char ().isspace () && !line_end.ends_line ()) {
            line_end.forward_char ();
        }

        if (!line_start.equal (line_end)) {
            view.buffer.delete (ref line_start, ref line_end);
        }

        view.buffer.end_user_action ();
    }

    public bool is_trigger (GtkSource.View view, Gtk.TextIter location, Gdk.ModifierType state, uint keyval) {
        return (keyval == Gdk.Key.Return || keyval == Gdk.Key.KP_Enter);
    }

}