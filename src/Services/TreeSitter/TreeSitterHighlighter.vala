using Gtk;
using GtkSource;

public class TreeSitterHighlighter : Object {
    private View view;
    private Buffer buffer;
    private TreeSitter.Parser parser;
    private TreeSitter.Tree? tree = null;

    public TreeSitterHighlighter(View view, TreeSitter.Language language) {
        this.view = view;
        this.buffer = (Buffer)view.get_buffer();

        // 1. Настройка парсера (например, для C)
        parser = new TreeSitter.Parser();
        parser.set_language(language);

        // 2. Слушаем изменения в буфере
        buffer.changed.connect(on_buffer_changed);
        on_buffer_changed();

        // Отключаем встроенную подсветку GtkSourceView
        buffer.highlight_syntax = false;
    }

    private void on_buffer_changed() {
        // 3. Парсим весь текст (для простоты примера)
        // В реальном приложении используйте ts_tree_edit для инкрементальности
        this.tree = parser.parse_string(null, buffer.text.data);

        apply_highlighting();
    }

    private void apply_highlighting() {
        if (tree == null) return;

        // 4. Очистка старых тегов (в реальном коде лучше делать только для грязной зоны)
        TextIter start, end;
        buffer.get_bounds(out start, out end);
        buffer.remove_all_tags(start, end);

        // 5. Рекурсивный обход дерева или использование Queries
        traverse_node(tree.root_node());
    }

    private void traverse_node(TreeSitter.Node node) {
        // Пример: подсвечиваем типы узлов "identifier"
        if (node.type() == "identifier") {
            highlight_range(node, "def:identifier");
        }

        for (uint i = 0; i < node.child_count(); i++) {
            traverse_node(node.child(i));
        }
    }

    private void highlight_range(TreeSitter.Node node, string style_name) {
        TextIter s_iter, e_iter;
        get_iters_from_ts_node(buffer, node, out s_iter, out e_iter);

        // Получаем тег из текущей схемы стиля GtkSourceView
        var scheme = buffer.style_scheme;
        var style = scheme.get_style(style_name);

        if (style != null) {
            // 2. Создаем тег или ищем существующий
            var tag = buffer.tag_table.lookup(style_name);
            if (tag == null) {
                tag = new Gtk.TextTag(style_name);
                buffer.tag_table.add(tag);
            }

            // 3. Копируем свойства из GtkSourceStyle в GtkTextTag
            apply_style_to_tag(style, tag);
            buffer.apply_tag(tag, s_iter, e_iter);
        }

        // Здесь нужно создать или получить GtkTextTag на основе GtkSourceStyle
        // и применить его: buffer.apply_tag(tag, s_iter, e_iter);
    }

    public static void get_iters_from_ts_node(TextBuffer buffer, TreeSitter.Node node,
                                              out TextIter start_iter, out TextIter end_iter) {
        start_iter = get_iter_at_ts_point(buffer, (int)node.start_point().row, (int)node.start_point().column);
        end_iter = get_iter_at_ts_point(buffer, (int)node.end_point().row, (int)node.end_point().column);
    }

    private static TextIter get_iter_at_ts_point(TextBuffer buffer, int row, int byte_col) {
        TextIter iter;

        // 1. Переходим к началу нужной строки (row)
        buffer.get_iter_at_line(out iter, row);

        // 2. Двигаемся вперед по байтам внутри этой строки.
        // Метод set_line_index оперирует именно БАЙТОВЫМ смещением от начала строки.
        iter.set_line_index(byte_col);

        return iter;
    }

    private void apply_style_to_tag(GtkSource.Style style, Gtk.TextTag tag) {
        // Цвет текста (Foreground)
        if (style.foreground_set) {
            tag.foreground = style.foreground;
        }

        // Цвет фона (Background)
        if (style.background_set) {
            tag.background = style.background;
        }

        // Жирный шрифт
        if (style.bold_set) {
            tag.weight = style.bold ? Pango.Weight.BOLD : Pango.Weight.NORMAL;
        }

        // Курсив
        if (style.italic_set) {
            tag.style = style.italic ? Pango.Style.ITALIC : Pango.Style.NORMAL;
        }
    }

}
