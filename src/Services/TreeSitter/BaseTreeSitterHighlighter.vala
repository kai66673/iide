using TreeSitter;

public abstract class Iide.BaseTreeSitterHighlighter : Object {
    // Нативные структуры Tree-sitter
    protected Parser parser;
    protected TreeSitter.Tree? tree;
    protected Query? query;
    protected QueryCursor cursor;

    // GTK объекты
    protected GtkSource.Buffer buffer;
    protected SourceView view;

    // Оптимизированный кэш: [capture_index, theme_index]
    // theme_index: 1 - Light, 0 - Dark
    private Gtk.TextTag ? [, ] capture_tags;

    // Глобальный указатель на текущую тему (может обновляться из DocumentManager)
    private int current_theme_index = 0;

    // Таймер для Debounce
    private uint highlight_timeout_id = 0;
    private const uint DEBOUNCE_MS = 150;

    private void set_color_theme () {
        var color_scheme = SettingsService.get_instance ().color_scheme;
        current_theme_index = color_scheme != ColorScheme.LIGHT ? 1 : 0;
        run_highlighting ();
    }

    protected BaseTreeSitterHighlighter (SourceView view) {
        view.set_insert_spaces_instead_of_tabs (true);
        view.set_tab_width (4);
        view.set_smart_backspace (true);

        this.view = view;
        this.buffer = (GtkSource.Buffer) view.get_buffer ();

        this.parser = new Parser ();
        this.cursor = new QueryCursor ();

        unowned Language lang = get_ts_language ();
        if (lang != null) {
            this.parser.set_language (lang);
            load_query (lang);
            // Подготавливаем индексный мост сразу после загрузки Query
            prepare_capture_mapping ();
        }

        // Устанавливаем тему цвета и подписываемся на изменение схемы цветов
        set_color_theme ();
        this.buffer.notify["style-scheme"].connect_after (set_color_theme);

        // Подключаемся к изменениям текста
        this.buffer.changed.connect_after (on_buffer_changed);

        // Если передано View, подписываемся на скроллинг для инкрементальной покраски
        if (view != null) {
            view.hadjustment.value_changed.connect (on_viewport_changed);
            view.vadjustment.value_changed.connect (on_viewport_changed);
        }
    }

    // Абстрактные методы для реализации в подклассах (Vala, Cpp и т.д.)
    protected abstract unowned Language ? get_ts_language ();
    protected abstract string get_query_filename ();
    protected abstract string query_source ();

    private void load_query (Language lang) {
        string source = query_source ();

        uint32 error_offset;
        QueryError error_type;
        this.query = new Query (lang, source, (uint32) source.length, out error_offset, out error_type);

        if (error_type != QueryError.None) {
            warning ("TreeSitter Query Error at %u: %s", error_offset, error_type.to_string ());
        }
    }

    private void prepare_capture_mapping () {
        if (query == null)return;

        uint32 count = query.capture_count ();
        capture_tags = new Gtk.TextTag ? [count, 2];
        var style_service = StyleService.get_instance ();

        for (uint32 i = 0; i < count; i++) {
            uint32 name_len;
            string name = query.capture_name_for_id (i, out name_len);

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

    private void on_buffer_changed () {
        if (highlight_timeout_id > 0) {
            Source.remove (highlight_timeout_id);
        }

        highlight_timeout_id = Timeout.add (DEBOUNCE_MS, () => {
            run_highlighting ();
            highlight_timeout_id = 0;
            return Source.REMOVE;
        });
    }

    private void on_viewport_changed () {
        // При скроллинге красим без большой задержки
        run_highlighting ();
    }

    private void run_highlighting () {
        Gtk.TextIter start, end;
        buffer.get_bounds (out start, out end);
        string content = buffer.get_text (start, end, false);

        // Инкрементальный парсинг: передаем старое дерево для ускорения
        var new_tree = parser.parse_string (null, content.data);
        tree = (owned) new_tree;

        if (tree != null && query != null) {
            apply_highlights ();
        }
    }

    private void apply_highlights () {
        // if (view != null) {
        //// Оптимизация: красим только то, что видит пользователь
        // Gdk.Rectangle visible_rect;
        // view.get_visible_rect (out visible_rect);

        // Gtk.TextIter start_iter, end_iter;
        // int line_top;
        // view.get_line_at_y (out start_iter, visible_rect.y, out line_top);
        // view.get_line_at_y (out end_iter, visible_rect.y + visible_rect.height, out line_top);
        // end_iter.forward_to_line_end ();

        // cursor.set_byte_range (
        // (uint32) get_absolute_byte_offset (start_iter),
        // (uint32) get_absolute_byte_offset (end_iter)
        // );
        // }

        Gtk.TextIter start, end;
        buffer.get_bounds (out start, out end);
        buffer.remove_all_tags (start, end);

        cursor.exec (query, tree.root_node ());

        QueryMatch match;
        while (cursor.next_match (out match)) {
            foreach (var capture in match.captures) {
                // Мгновенное получение тега по двум индексам без поиска в словарях
                var tag = capture_tags[capture.index, current_theme_index];
                if (tag != null) {
                    apply_tag_fast (capture.node, tag);
                }
            }
        }
    }

    private void apply_tag_fast (TreeSitter.Node node, Gtk.TextTag tag) {
        Gtk.TextIter start, end;

        // Получаем итераторы по абсолютному БАЙТОВОМУ смещению
        get_iters_from_ts_node (buffer, node, out start, out end);

        buffer.apply_tag (tag, start, end);
    }

    public static void get_iters_from_ts_node (Gtk.TextBuffer buffer, TreeSitter.Node node,
                                               out Gtk.TextIter start_iter, out Gtk.TextIter end_iter) {
        buffer.get_iter_at_line (out start_iter, (int) node.start_point ().row);
        start_iter.set_line_index ((int) node.start_point ().column);

        buffer.get_iter_at_line (out end_iter, (int) node.end_point ().row);
        end_iter.set_line_index ((int) node.end_point ().column);
    }

    ~BaseTreeSitterHighlighter () {
        // Явное зануление для вызова free_functions из VAPI
        this.parser = null;
        this.tree = null;
        this.query = null;
        this.cursor = null;
    }
}
