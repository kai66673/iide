using TreeSitter;

/**
 * Отвечает за рендеринг синтаксической подсветки на основе результатов Query.
 * Инкапсулирует логику применения тегов к GtkSource.Buffer.
 */
public class Iide.TreeSitterRenderer : Object {
    protected GtkSource.Buffer buffer;
    protected SourceView view;
    protected StyleService style_service;
    protected QueryCursor cursor;
    protected int current_theme_index = 0;
    
    // Debounce для оптимизации
    private uint highlight_timeout_id = 0;
    private const uint DEBOUNCE_MS = 150;
    
    public TreeSitterRenderer (SourceView view, StyleService style_service) {
        this.view = view;
        this.buffer = (GtkSource.Buffer) view.get_buffer ();
        this.style_service = style_service;
        this.cursor = new QueryCursor ();
        
        bind_signals ();
    }
    
    private void bind_signals () {
        buffer.notify["style-scheme"].connect_after (() => {
            update_theme ();
        });
    }
    
    public void set_theme_index (int theme_index) {
        current_theme_index = theme_index;
    }
    
    public int get_theme_index () {
        return current_theme_index;
    }
    
    private void update_theme () {
        var color_scheme = SettingsService.get_instance ().color_scheme;
        current_theme_index = color_scheme != ColorScheme.LIGHT ? 1 : 0;
        flush_changes ();
    }
    
    /**
     * Применяет теги подсветки ко всему документу.
     */
    public void render_full (Query query, TreeSitter.Node root_node) {
        Gtk.TextIter start, end;
        buffer.get_bounds (out start, out end);
        
        clear_highlighter_tags (start, end);
        
        cursor = new QueryCursor ();
        cursor.exec (query, root_node);
        
        QueryMatch match;
        while (cursor.next_match (out match)) {
            foreach (var capture in match.captures) {
                apply_tag_fast (capture.node, get_capture_tag (capture));
            }
        }
    }
    
    /**
     * Оптимизированный рендеринг только видимой области экрана.
     */
    public void render_viewport (Query query, TreeSitter.Node root_node) {
        if (!get_viewport_bounds (out Gtk.TextIter visible_start, out Gtk.TextIter visible_end)) {
            return;
        }
        
        Utils utils = new Utils ();
        uint32 viewport_start_byte = utils.get_byte_offset_safe (visible_start);
        uint32 viewport_end_byte = utils.get_byte_offset_safe (visible_end);
        
        clear_highlighter_tags (visible_start, visible_end);
        
        cursor = new QueryCursor ();
        cursor.exec (query, root_node);
        
        QueryMatch match;
        while (cursor.next_match (out match)) {
            foreach (var capture in match.captures) {
                uint32 node_start = capture.node.start_byte ();
                uint32 node_end = capture.node.end_byte ();
                
                if (node_end < viewport_start_byte || node_start > viewport_end_byte) {
                    continue;
                }
                
                apply_tag_fast (capture.node, get_capture_tag (capture));
            }
        }
    }
    
    /**
     * Мгновенный рендер при скролле без перепарсинга.
     */
    public void render_viewport_only () {
        // Вызывается из BaseTreeSitterHighlighter при скролле
        // Логика делегируется render_viewport с текущим деревом
    }
    
    /**
     * Очищает все теги подсветки в диапазоне.
     */
    public void clear_highlighter_tags (Gtk.TextIter start, Gtk.TextIter end) {
        Gtk.TextIter it = start;
        remove_syntax_tags_at_iter (buffer, it, start, end);
        
        while (it.forward_to_tag_toggle (null) && it.compare (end) < 0) {
            remove_syntax_tags_at_iter (buffer, it, start, end);
        }
    }
    
    private void remove_syntax_tags_at_iter (Gtk.TextBuffer buffer, Gtk.TextIter it, 
                                              Gtk.TextIter range_start, Gtk.TextIter range_end) {
        var active_tags = it.get_tags ();
        
        foreach (var tag in active_tags) {
            if (tag.name != null && !tag.name.has_prefix ("$")) {
                Gtk.TextIter toggle_start = it;
                Gtk.TextIter toggle_end = it;
                
                if (!toggle_start.has_tag (tag) || toggle_start.compare (range_start) < 0) {
                    toggle_start = range_start;
                }
                
                toggle_end.forward_to_tag_toggle (tag);
                if (toggle_end.compare (range_end) > 0) {
                    toggle_end = range_end;
                }
                
                buffer.remove_tag (tag, toggle_start, toggle_end);
            }
        }
    }
    
    /**
     * Применяет тег к узлу.
     * Делегирует получение тега подклассам через виртуальный метод.
     */
    protected virtual Gtk.TextTag? get_capture_tag (TreeSitter.QueryCapture capture) {
        // Должен быть переопределен в подклассах для конкретных языков
        return null;
    }
    
    private void apply_tag_fast (TreeSitter.Node node, Gtk.TextTag? tag) {
        if (tag == null)
            return;

        get_iters_from_ts_node (buffer, node, 
                                   out Gtk.TextIter start, 
                                   out Gtk.TextIter end);
        buffer.apply_tag (tag, start, end);
    }
    
    /**
     * Получает Gtk.TextIter из координат Tree-sitter узла.
     */
    public static void get_iters_from_ts_node (Gtk.TextBuffer buffer, TreeSitter.Node node,
                                               out Gtk.TextIter start_iter, out Gtk.TextIter end_iter) {
        buffer.get_iter_at_line (out start_iter, (int) node.start_point ().row);
        start_iter.set_line_index ((int) node.start_point ().column);

        buffer.get_iter_at_line (out end_iter, (int) node.end_point ().row);
        end_iter.set_line_index ((int) node.end_point ().column);
    }
    
    /**
     * Получает границы видимой области вьюпорта.
     */
    protected bool get_viewport_bounds (out Gtk.TextIter visible_start, out Gtk.TextIter visible_end) {
        Gdk.Rectangle visible_rect;
        view.get_visible_rect (out visible_rect);

        view.get_iter_at_location (out visible_start, visible_rect.x, visible_rect.y);
        view.get_iter_at_location (out visible_end, visible_rect.x + visible_rect.width, 
                                    visible_rect.y + visible_rect.height);

        visible_start.set_line_offset (0);
        visible_end.forward_to_line_end ();
        if (!visible_end.is_end ()) {
            visible_end.forward_char ();
        }
        
        return true;
    }
    
    /**
     * Планирует отложенный рендеринг (debounce).
     */
    public void schedule_render (owned GLib.SourceFunc callback) {
        if (highlight_timeout_id > 0) {
            GLib.Source.remove (highlight_timeout_id);
        }

        highlight_timeout_id = GLib.Timeout.add (DEBOUNCE_MS, () => {
            callback ();
            highlight_timeout_id = 0;
            return GLib.Source.REMOVE;
        });
    }
    
    /**
     * Принудительно выполняет отложенный рендеринг.
     */
    public void flush_changes () {
        if (highlight_timeout_id > 0) {
            GLib.Source.remove (highlight_timeout_id);
            highlight_timeout_id = 0;
        }
    }
    
    ~TreeSitterRenderer () {
        cursor = null;
    }
}
