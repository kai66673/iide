/*
 */

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

    // Общий метод для расчета отступа (можно сделать дефолтным)
    public virtual string calculate_indent (TreeSitter.Tree? tree, Gtk.TextIter iter, int indent_width) {
        if (tree == null || query == null)
            return ""; // TODO: расчитать из предыдущей строки

        // Получаем абсолютное байтовое смещение (твой проверенный способ)
        unowned var buffer = iter.get_buffer ();
        Gtk.TextIter start_buf;
        buffer.get_start_iter (out start_buf);
        uint32 byte_offset = (uint32) buffer.get_slice (start_buf, iter, false).length;

        if (byte_offset > 0)
            byte_offset--; // Смотрим на символ ПЕРЕД нажатием Enter

        uint32 base_node_start_byte = 0;
        uint32 base_node_row = 0;
        bool found = false;

        // 1. Ищем самый глубокий узел-родитель, требующий отступа
        var cursor = new TreeSitter.QueryCursor ();
        cursor.set_byte_range (byte_offset, byte_offset + 1);
        cursor.exec (this.query, tree.root_node ());

        TreeSitter.QueryMatch match;
        int mi = 0;
        while (cursor.next_match (out match)) {
            for (int i = 0; i < match.capture_count; i++) {
                LoggerService.get_instance ().info ("INDENT", "match index - %d; capture index - %d".printf (mi, i));
                unowned TreeSitter.Node node = match.captures[i].node;
                LoggerService.get_instance ().info ("INDENT", "%s - %d".printf (node.type (), (int) node.start_point ().row));
                // Ищем узел, который охватывает курсор
                if (node.start_byte () <= byte_offset && node.end_byte () > byte_offset) {
                    // Нам нужен самый вложенный (начался позже всех)
                    if (!found || node.start_byte () >= base_node_start_byte) {
                        base_node_row = node.start_point ().row;
                        base_node_start_byte = node.start_byte ();
                        found = true;
                    }
                }
            }
            mi++;
        }

        LoggerService.get_instance ().info ("INDENT", " --> %d".printf ((int) base_node_row));

        if (!found)
            return "";

        // 2. Получаем отступ строки, на которой НАЧИНАЕТСЯ базовый узел
        uint32 start_row = base_node_row;
        Gtk.TextIter line_iter;
        buffer.get_iter_at_line (out line_iter, (int) start_row);

        Gtk.TextIter line_end = line_iter;
        line_end.forward_to_line_end ();
        string line_text = line_iter.get_text (line_end);

        message ("INDENT: lt = \"%s\" (len = %d)".printf (line_text, line_text.length));

        string base_indent = "";
        int ws_count = 0;
        while (line_text.length > ws_count) {
            var c = line_text[ws_count];
            if (c.isspace ()) {
                base_indent += c.to_string ();
                ws_count++;
            } else {
                break;
            }
        }

        // 3. Целевой отступ = отступ родителя + шаг
        if (indent_width < 0) {
            indent_width = 4; // TODO: from settings...
        }
        string target_indent = base_indent + string.nfill (indent_width, ' ');

        // 4. Учет "разрыва": вычитаем то, что уже есть на новой строке
        Gtk.TextIter current_line_start = iter;
        current_line_start.set_line_offset (0);

        Gtk.TextIter first_char = current_line_start;
        while (!first_char.equal (iter)) {
            if (!first_char.get_char ().isspace ())break;
            first_char.forward_char ();
        }
        string existing_indent = current_line_start.get_text (first_char);

        if (target_indent.has_prefix (existing_indent)) {
            return target_indent.substring (existing_indent.length);
        }

        return target_indent;
    }
}