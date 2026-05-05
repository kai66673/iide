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

    // Общий метод для расчета отступа (можно сделать дефолтным)
    public virtual string calculate_indent (TreeSitter.Tree? tree, Gtk.TextIter iter, int indent_width) {
        if (tree == null || query == null)return "";

        var buffer = iter.get_buffer ();

        // 1. Ищем "якорь" — ближайшую непустую строку выше текущей позиции
        Gtk.TextIter anchor_iter = iter;
        bool found_anchor = false;

        while (anchor_iter.backward_line ()) {
            Gtk.TextIter line_end = anchor_iter;
            line_end.forward_to_line_end ();
            string content = buffer.get_text (anchor_iter, line_end, false).strip ();
            if (content.length > 0) {
                found_anchor = true;
                break;
            }
        }

        // Если выше ничего нет (начало файла), отступ не нужен
        if (!found_anchor)return "";

        // 2. Получаем базовый отступ якорной строки
        string base_indent = get_line_indent_text (anchor_iter);

        // 3. Решаем, нужно ли УВЕЛИЧИВАТЬ отступ (increase_indent)
        Gtk.TextIter anchor_end = anchor_iter;
        anchor_end.forward_to_line_end ();
        uint32 anchor_end_byte = get_byte_offset_safe (anchor_end);

        bool should_increase = false;

        if (anchor_end_byte > 0) {
            var cursor = new TreeSitter.QueryCursor ();
            // Смотрим, что находится в самом конце якорной строки (перед переводом строки)
            cursor.set_byte_range (anchor_end_byte - 1, anchor_end_byte);
            cursor.exec (this.query, tree.root_node ());

            TreeSitter.QueryMatch match;
            while (cursor.next_match (out match)) {
                if (match.capture_count > 0) {
                    // Берем узел, который поймал Query (@indent.begin)
                    unowned TreeSitter.Node node = match.captures[0].node;

                    // ПРОВЕРКА: Добавляем отступ только если узел начался
                    // именно на этой якорной строке (т.е. это заголовок блока)
                    if (node.start_point ().row == (uint32) anchor_iter.get_line ()) {
                        should_increase = true;
                        break;
                    }
                }
            }
        }

        // 4. Формируем результат
        if (should_increase) {
            int width = indent_width > 0 ? indent_width : 4;
            return base_indent + string.nfill (width, ' ');
        }

        // Иначе просто копируем отступ якорной строки
        return base_indent;
    }

    public IndentInstruction need_indent (TreeSitter.Tree? tree, Gtk.TextIter iter) {
        IndentInstruction instr = { "", 0, 0 };
        var buffer = iter.get_buffer ();

        // 1. Считаем "паразитов" (пробелы/табы) в конце ПРЕДЫДУЩЕЙ строки
        // Мы находимся в Idle, итератор iter стоит в начале новой строки (offset 0)
        Gtk.TextIter ws_check = iter;
        if (ws_check.backward_char ()) { // Ушли за вставленный '\n'
            // Считаем пробелы от конца строки назад к тексту
            while (ws_check.backward_char () && ws_check.get_char ().isspace () && !ws_check.ends_line ()) {
                instr.trim_chars++;
            }
        }

        // 2. Ищем "якорь" — ближайшую непустую строку ВЫШЕ текущей
        Gtk.TextIter anchor = iter;
        bool found_anchor = false;
        while (anchor.backward_line ()) {
            Gtk.TextIter line_end = anchor;
            line_end.forward_to_line_end ();
            string content = buffer.get_text (anchor, line_end, false).strip ();
            if (content.length > 0) {
                found_anchor = true;
                break;
            }
        }

        // Если файл пустой или мы в самом начале — делать нечего
        if (!found_anchor)return instr;

        // 3. Получаем базовый отступ якорной строки
        instr.base_indent = get_line_indent_text (anchor);

        // 4. Tree-sitter АНАЛИЗ: нужно ли увеличить уровень вложенности?
        Gtk.TextIter anchor_end = anchor;
        anchor_end.forward_to_line_end ();
        // Смещение конца якорной строки (учитывая, что \n уже в буфере)
        uint32 end_byte = get_byte_offset_safe (anchor_end);

        if (end_byte > 0) {
            var cursor = new TreeSitter.QueryCursor ();

            // ВАЖНО: Смотрим на 2 байта назад от конца якорной строки.
            // 1-й байт — это \n, 2-й байт — это символ ПЕРЕД \n (наше двоеточие).
            uint32 check_pos = end_byte > 1 ? end_byte - 1 : 0;
            cursor.set_byte_range (check_pos, end_byte);
            cursor.exec (this.query, tree.root_node ());

            TreeSitter.QueryMatch match;
            while (cursor.next_match (out match)) {
                for (int i = 0; i < match.capture_count; i++) {
                    unowned TreeSitter.Node node = match.captures[i].node;

                    // Проверяем, что найденный узел начался именно на этой строке.
                    // Это отсекает лишние инденты внутри уже существующих блоков.
                    if (node.start_point ().row == (uint32) anchor.get_line ()) {
                        instr.level_delta = 1;
                        return instr; // Нашли совпадение — сразу возвращаем инструкцию
                    }
                }
            }
        }

        return instr;
    }
}