/*
*/

public abstract class Iide.SimpleTreeSitterHighlighter: BaseTreeSitterHighlighter {
    // Оптимизированный кэш: [capture_index, theme_index]
    // theme_index: 1 - Light, 0 - Dark
    protected Gtk.TextTag ? [, ] capture_tags;
    protected int brackets_capture_index = -1;

    
    protected SimpleTreeSitterHighlighter (SourceView view) {
        base(view);
    }

    protected override void prepare_capture_mapping () {
        if (query == null)
            return;

        uint32 count = query.capture_count ();
        capture_tags = new Gtk.TextTag ? [count, 2];

        for (uint32 i = 0; i < count; i++) {
            uint32 name_len;
            string name = query.capture_name_for_id (i, out name_len);

            if (name == "punctuation.bracket")
                brackets_capture_index = (int) i;

            // Кэшируем теги для обеих тем по индексу захвата
            capture_tags[i, 0] = style_service.get_tag (name, 0);
            capture_tags[i, 1] = style_service.get_tag (name, 1);

            // Фолбэк для составных имен (например, @function.method -> @function)
            if (capture_tags[i, 0] == null && name.contains (".")) {
                string base_name = name.split (".")[0];
                capture_tags[i, 0] = style_service.get_tag (base_name, 0);
                capture_tags[i, 1] = style_service.get_tag (base_name, 1);
            }
        }
    }

    protected override Gtk.TextTag? capture_tag(TreeSitter.QueryCapture capture, int theme_index) {
        if (capture.index == brackets_capture_index) {
            int lvl = (get_nesting_level (capture.node) % 5); // Цикл по 5 цветам
            return style_service.get_bracket_tag (lvl, theme_index);
        } 

        return capture_tags[capture.index, theme_index];
    }

    private int get_nesting_level (TreeSitter.Node node) {
        int level = 0;
        TreeSitter.Node? parent = node.parent ();
        while (parent != null && !parent.is_null ()) {
            string type = parent.type ();
            // Считаем вложенность только по блокам, спискам аргументов и т.д.
            if (type == "block" || type == "argument_list" || type == "parameters" || type == "tuple_pattern") {
                level++;
            }
            parent = parent.parent ();
        }
        return level;
    }

}