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

    private TreeSitter.Input ts_input;

    // Оптимизированный кэш: [capture_index, theme_index]
    // theme_index: 1 - Light, 0 - Dark
    private Gtk.TextTag ? [, ] capture_tags;

    // Глобальный указатель на текущую тему (может обновляться из DocumentManager)
    private int current_theme_index = 0;

    // Таймер для Debounce
    private uint highlight_timeout_id = 0;
    private const uint DEBOUNCE_MS = 150;
    private Gee.ArrayList<TreeSitter.Range?> pending_ui_ranges;
    private ulong scroll_signal_id = 0;

    // Список структур Range из Tree-sitter для хранения истории
    private Gee.ArrayQueue<TreeSitter.Range?> selection_stack = new Gee.ArrayQueue<TreeSitter.Range?> ();
    private bool is_internal_selection_change = false;

    private Gee.List<SourceNodeItem?> last_crumbs = null;
    public signal void breadcrumbs_changed (Gee.List<SourceNodeItem?> crumbs);

    // Сигнал, сообщающий UI-компонентам, что структура блоков изменилась
    public signal void folding_structure_updated (Gee.List<IndentBlock?> blocks);

    // Внутренний кэш блоков кода
    protected Gee.List<IndentBlock?> cached_blocks;

    private void set_color_theme () {
        var color_scheme = SettingsService.get_instance ().color_scheme;
        current_theme_index = color_scheme != ColorScheme.LIGHT ? 1 : 0;
        if (highlight_timeout_id > 0) {
            Source.remove (highlight_timeout_id);
        }
        initial_rehighlight ();
    }

    private static string ? ts_read_callback (void* payload, uint32 byte_index, Point position, out uint32 bytes_read) {
        var self = (BaseTreeSitterHighlighter) payload;
        var buffer = self.buffer;
        bytes_read = 0;

        Gtk.TextIter iter;
        buffer.get_start_iter (out iter);

        // 1. ИЩЕМ ИТЕРАТОР ПО АБСОЛЮТНОМУ БАЙТОВОМУ ИНДЕКСУ
        // Вместо капризного get_iter_at_line по структуре Point, мы используем 
        // внутренний постраничный/построчный поиск самого GTK, замеряя байты.
        // Чтобы сделать это максимально быстро, прыгаем по строкам через get_bytes_in_line
        uint32 accumulated_bytes = 0;
        while (accumulated_bytes + (uint32) iter.get_bytes_in_line () <= byte_index) {
            accumulated_bytes += (uint32) iter.get_bytes_in_line ();
            if (!iter.forward_line ()) {
                break; // Дошли до конца файла
            }
        }

        // Добираемся до точного байта внутри найденной строки посимвольно
        // (Этот внутренний хвостик обычно равен всего нескольким байтам)
        while (accumulated_bytes < byte_index) {
            int current_char_bytes = iter.get_bytes_in_line () - iter.get_line_index ();
            // Защита от бесконечного цикла на краю строки
            if (current_char_bytes <= 0) break; 
            
            // Продвигаем итератор вперед на один символ буфера (включая невидимые!)
            if (!iter.forward_char ()) break;
            
            // Пересчитываем глобальный байтовый оффсет через наш get_byte_offset_safe
            accumulated_bytes = get_byte_offset_safe (iter);
        }

        if (iter.is_end ()) return null;

        // 2. ОПРЕДЕЛЯЕМ КОНЕЦ ЧТЕНИЯ ЧАНКА (Блока текста)
        // Читаем текст порциями — от текущей позиции до конца текущей строки (включая \n)
        Gtk.TextIter end = iter;
        int total_line_bytes = end.get_bytes_in_line ();
        end.set_line_index (total_line_bytes); // Встаем строго в конец физической строки памяти буфера

        // Запрашиваем текст. Метод get_text (в отличие от get_slice) 
        // ГАРАНТИРОВАННО вернет все символы, включая скрытые тегом $FOLD_HIDE!
        string chunk = buffer.get_text (iter, end, false);
        bytes_read = (uint32) chunk.length; // В Vala это длина в байтах UTF-8

        return bytes_read > 0 ? chunk : null;
    }

    protected BaseTreeSitterHighlighter (SourceView view) {
        view.set_insert_spaces_instead_of_tabs (true);
        view.set_tab_width (4);
        view.set_smart_backspace (true);

        this.view = view;
        this.buffer = (GtkSource.Buffer) view.get_buffer ();

        // Заполняем структуру один раз
        this.ts_input = {};
        this.ts_input.payload = (void*) this;
        this.ts_input.read = ts_read_callback;
        this.ts_input.encoding = TreeSitter.InputEncoding.UTF8;

        this.parser = new Parser ();
        this.cursor = new QueryCursor ();
        
        this.cached_blocks = new Gee.ArrayList<IndentBlock?> ();
        this.pending_ui_ranges = new Gee.ArrayList<TreeSitter.Range?> ();

        // Определяем язык
        unowned Language lang = get_ts_language ();
        this.parser.set_language (lang);
        // Загружаем Query
        load_query (lang);
        // Подготавливаем индексный мост сразу после загрузки Query
        prepare_capture_mapping ();

        // Устанавливаем тему цвета и подписываемся на изменение схемы цветов
        set_color_theme ();
        this.buffer.notify["style-scheme"].connect_after (set_color_theme);

        buffer.notify["cursor-position"].connect (() => {
            // Если позиция курсора изменилась не через наши методы expand/shrink — чистим стек
            if (!is_internal_selection_change) {
                selection_stack.clear ();
            }
        });

        buffer.notify["cursor-position"].connect (update_breadcrumbs);

        this.buffer.changed.connect (this.on_buffer_changed);
        this.bind_highlighter_signals ();
    }

    private void bind_highlighter_signals () {
        // Получаем вертикальный adjustment текстового поля
        var vadjustment = this.view.get_vadjustment ();

        // Отписываемся от старого сигнала, если он был
        if (this.scroll_signal_id != 0 && vadjustment != null) {
            vadjustment.disconnect (this.scroll_signal_id);
        }

        // Подписываемся на скроллинг
        this.scroll_signal_id = vadjustment.value_changed.connect (() => {
            // Вызываем максимально облегченный рендер только для прокрутки
            this.render_viewport_only ();
        });
    }

    public Gee.List<IndentBlock?> get_cached_indent_blocks () {
        return this.cached_blocks;
    }

    // Абстрактные методы для реализации в подклассах (Vala, Cpp и т.д.)
    protected abstract unowned Language get_ts_language ();
    protected abstract string query_source ();

    // Абстрактный метод для фильтрации узлов Breadcrumbs
    protected abstract bool is_container_node (string node_type);

    // Точка входа для обновления структуры фолдинга документа
    protected void update_document_structure () {
        this.cached_blocks.clear ();

        // Получаем корневой узел дерева через имеющиеся биндинги
        var root = this.tree.root_node ();
        if (root.is_null ()) return;

        // Запускаем рекурсивный обход с начальным уровнем отступа 0
        this.collect_foldable_blocks (root, 0);

        // Генерируем сигнал для Gutter и Overlay
        this.folding_structure_updated (this.cached_blocks);
    }

    private void collect_foldable_blocks (TreeSitter.Node parent, int current_indent) {
        // Используем ваш паттерн итерации по именованным узлам
        for (uint32 i = 0; i < parent.named_child_count (); i++) {
            var child = parent.named_child (i);

            if (child.is_null ()) continue;

            string type = child.type ();
            bool is_foldable = false;

            // Проверяем, нужно ли сворачивать этот тип узла
            if (this.is_foldable_node_type (type)) {
                var start_point = child.start_point ();
                var end_point = child.end_point ();

                // Блок имеет смысл сворачивать, только если он занимает больше 1 строки
                if (end_point.row > start_point.row) {
                    var block = IndentBlock () {
                        start_line = (int) start_point.row,
                        end_line = (int) end_point.row,
                        indent_level = current_indent
                    };
                    
                    // Добавляем в плоский кэш для UI
                    this.cached_blocks.add (block);
                    is_foldable = true;
                }
            }

            // КЛЮЧЕВОЙ МОМЕНТ СИНХРОНИЗАЦИИ ОТСТУПОВ:
            // Если текущий узел оказался сворачиваемым (например, класс или функция),
            // все его внутренние дочерние блоки должны получить уровень отступа на 1 больше.
            int next_indent = is_foldable ? current_indent + 1 : current_indent;

            // Рекурсивно идем вглубь дочернего узла
            if (child.named_child_count () > 0) {
                this.collect_foldable_blocks (child, next_indent);
            }
        }
    }

    // Виртуальный метод, переопределяемый в конкретных языковых подсвечниках (например, PythonHighlighter)
    protected virtual bool is_foldable_node_type (string type) {
        // Базовый дефолтный список для C-подобных языков
        return type == "compound_statement" || 
               type == "function_definition" || 
               type == "class_definition" ||
               type == "block";
    }

    // Виртуальный метод создания индентера
    public virtual GtkSource.Indenter? create_indenter() {
        return null;
    }

    public unowned TreeSitter.Tree? get_tree () {
        return tree; 
    }

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

    // Легковесный метод сбора блоков без вызова внешних сигналов
    private void update_document_structure_silent () {
        this.cached_blocks.clear ();
        var root = this.tree.root_node ();
        if (!root.is_null ()) {
            this.collect_foldable_blocks (root, 0);
        }
    }

    private void on_buffer_changed () {
        unowned TreeSitter.Tree? old_tree = this.tree;
        var new_tree = this.parser.parse (old_tree, this.ts_input);
        if (new_tree == null) return;

        this.tree = (owned) new_tree;

        var buffer = this.view.get_buffer ();
        var invisible_tag = buffer.get_tag_table ().lookup ("$FOLD_HIDE");

        if (invisible_tag != null && this.view.folding_gutter != null) {
            // Запрашиваем у Tree-sitter самый свежий плоский список блоков для нового состояния буфера
            // (Вызываем ваш рекурсивный метод сбора блоков прямо сейчас, чтобы получить актуальные cached_blocks)
            this.update_document_structure_silent (); 

            // Идем по списку физически свернутых блоков в гутере с конца, чтобы безопасно удалять элементы
            for (int i = this.view.folding_gutter.active_folds.size - 1; i >= 0; i--) {
                var fold = this.view.folding_gutter.active_folds[i];

                Gtk.TextIter current_start_iter;
                buffer.get_iter_at_mark (out current_start_iter, fold.start_mark);
                
                // Получаем строку, где СЕЙЧАС (после смещения) находится заголовок этого свернутого блока
                int current_header_line = current_start_iter.get_line () - 1;

                // Проверяем: видит ли Tree-sitter начало синтаксического блока на этой строке?
                bool block_still_exists = false;
                foreach (var block in this.cached_blocks) {
                    if (block.start_line == current_header_line) {
                        block_still_exists = true;
                        break;
                    }
                }

                // 2. АВТОРАЗВОРАЧИВАНИЕ: Если блок разрушен (заголовок стерт или изменен отступ)
                if (!block_still_exists) {
                    Gtk.TextIter s, e;
                    buffer.get_iter_at_mark (out s, fold.start_mark);
                    buffer.get_iter_at_mark (out e, fold.end_mark);

                    // Снимаем тег невидимости — код мгновенно раскрывается на экране!
                    buffer.remove_tag (invisible_tag, s, e);

                    // Удаляем маркеры из памяти буфера и очищаем список
                    fold.free_marks (buffer);
                    this.view.folding_gutter.active_folds.remove_at (i);
                    
                    // Форсируем ресайз вьюпорта, так как текст раскрылся
                    this.view.queue_resize ();
                }
            }
        }

        // Перезапускаем дебаунс
        if (this.highlight_timeout_id > 0) {
            GLib.Source.remove (this.highlight_timeout_id);
        }

        this.highlight_timeout_id = GLib.Timeout.add (DEBOUNCE_MS, () => {
            this.sync_and_render ();
            this.highlight_timeout_id = 0;
            return GLib.Source.REMOVE;
        });
    }
    
    public void flush_changes() {
        if (highlight_timeout_id > 0) {
            Source.remove (highlight_timeout_id);
        }
        sync_and_render ();
        highlight_timeout_id = 0;
    }

    private void initial_rehighlight () {
        Gtk.TextIter start, end;
        buffer.get_bounds (out start, out end);

        this.tree = parser.parse (null, ts_input);

        update_breadcrumbs ();
        update_document_structure ();

        // Удаляем старые теги
        clear_highlighter_tags (start, end);

        this.cursor = new QueryCursor ();
        cursor.exec (query, tree.root_node ());
        render_matches ();
    }

    private void clear_highlighter_tags (Gtk.TextIter start, Gtk.TextIter end) {
        Gtk.TextBuffer buffer = this.view.get_buffer();
        
        // Создаем рабочий итератор и встаем на начало диапазона очистки
        Gtk.TextIter it = start;
        
        // Оптимизация: если в начальной точке уже есть теги, обрабатываем их сразу
        this.remove_syntax_tags_at_iter (buffer, it, start, end);

        // Прыгаем только по точкам, где состояние тегов меняется (Toggle Points)
        // Это избавляет от посимвольного перебора текста
        while (it.forward_to_tag_toggle (null) && it.compare (end) < 0) {
            this.remove_syntax_tags_at_iter (buffer, it, start, end);
        }
    }

    private void remove_syntax_tags_at_iter (Gtk.TextBuffer buffer, Gtk.TextIter it, Gtk.TextIter range_start, Gtk.TextIter range_end) {
        // Получаем список всех тегов, активных в ДАННОЙ точке итератора
        var active_tags = it.get_tags();
        
        foreach (var tag in active_tags) {
            // Проверяем имя тега. Если он относится к раскраске Tree-sitter (все теги, кроме начинающихся с "$"):
            if (tag.name != null && !tag.name.has_prefix ("$")) {
                
                // Находим, где этот конкретный тег начался или закончился в буфере
                Gtk.TextIter toggle_start = it;
                Gtk.TextIter toggle_end = it;
                
                // Нам нужно определить границы применения этого тега вокруг текущей точки
                // Сдвигаемся назад к началу тега и вперед к его концу, но ОГРАНИЧИВАЕМСЯ рамками range_start/range_end
                if (!toggle_start.has_tag (tag) || toggle_start.compare (range_start) < 0) {
                    toggle_start = range_start;
                }
                
                // Ищем конец тега
                toggle_end.forward_to_tag_toggle (tag);
                if (toggle_end.compare (range_end) > 0) {
                    toggle_end = range_end;
                }
                
                // Удаляем точечно
                buffer.remove_tag (tag, toggle_start, toggle_end);
            }
        }
    }

    private void sync_and_render () {
        // 1. Обновляем структуру фолдинга и крошек (по всему актуальному дереву)
        this.update_breadcrumbs ();
        this.update_document_structure ();

        // 2. ВЫЧИСЛЯЕМ ВИДИМЫЙ ДИАПАЗОН СТРОК (Viewport)
        Gdk.Rectangle visible_rect;
        this.view.get_visible_rect (out visible_rect);

        Gtk.TextIter visible_start_iter;
        Gtk.TextIter visible_end_iter;
        
        // Переводим пиксели видимой области в текстовые итераторы
        this.view.get_iter_at_location (out visible_start_iter, visible_rect.x, visible_rect.y);
        this.view.get_iter_at_location (out visible_end_iter, visible_rect.x + visible_rect.width, visible_rect.y + visible_rect.height);

        // Расширяем границы до полных строк, чтобы очистка и подкраска не рвали токен посередине
        visible_start_iter.set_line_offset (0);
        visible_end_iter.forward_to_line_end ();
        if (!visible_end_iter.is_end ()) {
            visible_end_iter.forward_char ();
        }

        // 3. ОЧИСТКА ВИДИМОЙ ОБЛАСТИ
        // Стираем старую раскраску только на экране
        this.clear_highlighter_tags (visible_start_iter, visible_end_iter);

        // 4. ПОЛНОТЕКСТОВЫЙ СИНТАКСИЧЕСКИЙ ЗАПРОС (БЕЗ set_byte_range!)
        this.cursor = new QueryCursor ();
        
        // НЕ вызываем set_byte_range. Пусть Tree-sitter видит весь контекст файла.
        // Запускаем обход от корня
        this.cursor.exec (this.query, this.tree.root_node ());

        // 5. МОДИФИКАЦИЯ МЕТОДА НАЛОЖЕНИЯ ТЕГОВ
        // Передаем границы видимости в ваш метод отрисовки, 
        // чтобы он игнорировал токены, находящиеся далеко за пределами экрана
        uint32 viewport_start_byte = (uint32) get_byte_offset_safe (visible_start_iter);
        uint32 viewport_end_byte = (uint32) get_byte_offset_safe (visible_end_iter);

        this.render_matches_in_viewport (viewport_start_byte, viewport_end_byte);
    }
    
    private void render_matches () {
        QueryMatch match;
        while (cursor.next_match (out match)) {
            foreach (var capture in match.captures) {
                uint32 name_len;
                string capture_name = query.capture_name_for_id (capture.index, out name_len);

                Gtk.TextTag? tag = null;

                if (capture_name == "punctuation.bracket") {
                    int lvl = (get_nesting_level (capture.node) % 5) + 1; // Цикл по 5 цветам
                    tag = StyleService.get_instance ().get_tag ("bracket.lvl" + lvl.to_string (), current_theme_index);
                } else {
                    tag = capture_tags[capture.index, current_theme_index];
                }                if (tag != null) {
                    apply_tag_fast (capture.node, tag);
                }
            }
        }
    }

    private void render_matches_in_viewport (uint32 viewport_start_byte, uint32 viewport_end_byte) {
        QueryMatch match;
        while (cursor.next_match (out match)) {
            foreach (var capture in match.captures) {
                // ==========================================
                // ВЫСОКОПРОИЗВОДИТЕЛЬНЫЙ ФИЛЬТР VIEWPORT:
                // Получаем границы текущей ноды в байтах (O(1) в Tree-sitter)
                uint32 node_start = capture.node.start_byte ();
                uint32 node_end = capture.node.end_byte ();

                // Если токен находится целиком за пределами видимого экрана, 
                // мгновенно пропускаем его, экономя ресурсы процессора и GTK
                if (node_end < viewport_start_byte || node_start > viewport_end_byte) {
                    continue;
                }
                // ==========================================

                uint32 name_len;
                string capture_name = query.capture_name_for_id (capture.index, out name_len);

                Gtk.TextTag? tag = null;

                if (capture_name == "punctuation.bracket") {
                    int lvl = (get_nesting_level (capture.node) % 5) + 1; // Цикл по 5 цветам
                    tag = StyleService.get_instance ().get_tag ("bracket.lvl" + lvl.to_string (), current_theme_index);
                } else {
                    tag = capture_tags[capture.index, current_theme_index];
                }

                if (tag != null) {
                    apply_tag_fast (capture.node, tag);
                }
            }
        }
    }

    public void render_viewport_only () {
        // Если дерево еще не готово, ничего не делаем
        if (this.tree == null || this.tree.root_node ().is_null ()) return;

        // 1. ВЫЧИСЛЯЕМ ТЕКУЩИЙ ВИДИМЫЙ ЭКРАН
        Gdk.Rectangle visible_rect;
        this.view.get_visible_rect (out visible_rect);

        Gtk.TextIter visible_start_iter;
        Gtk.TextIter visible_end_iter;
        
        this.view.get_iter_at_location (out visible_start_iter, visible_rect.x, visible_rect.y);
        this.view.get_iter_at_location (out visible_end_iter, visible_rect.x + visible_rect.width, visible_rect.y + visible_rect.height);

        // Выравниваем по границам строк
        visible_start_iter.set_line_offset (0);
        visible_end_iter.forward_to_line_end ();
        if (!visible_end_iter.is_end ()) {
            visible_end_iter.forward_char ();
        }

        // 2. БАЙТОВЫЕ ОФФСЕТЫ ДЛЯ ФИЛЬТРА
        uint32 viewport_start_byte = get_byte_offset_safe (visible_start_iter);
        uint32 viewport_end_byte = get_byte_offset_safe (visible_end_iter);

        // 3. ОЧИСТКА ТОЛЬКО ТЕКУЩЕГО ЭКРАНА
        this.clear_highlighter_tags (visible_start_iter, visible_end_iter);

        // 4. ЗАПУСК КУРСОРA (Без тяжелых сопутствующих функций типа фолдинга)
        this.cursor = new QueryCursor ();
        this.cursor.exec (this.query, this.tree.root_node ());

        // Вызываем вашу оптимизированную функцию с фильтром по байтам
        this.render_matches_in_viewport (viewport_start_byte, viewport_end_byte);
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

    // Вспомогательный метод для работы с координатами напрямую
    private void get_iters_from_ts_node_coords (TreeSitter.Point start_p, TreeSitter.Point end_p,
                                                out Gtk.TextIter s, out Gtk.TextIter e) {
        buffer.get_iter_at_line (out s, (int) start_p.row);
        s.set_line_index ((int) start_p.column);

        buffer.get_iter_at_line (out e, (int) end_p.row);
        e.set_line_index ((int) end_p.column);
    }

    public bool handle_key_pressed(uint keyval, uint keycode, Gdk.ModifierType modifiers) {
        string opening = "";
        string closing = "";

        uint32 unicode = Gdk.keyval_to_unicode(keyval);

        // Опредяем пару на основе нажатой клавиши
        switch (unicode) {
            case '(': opening = "("; closing = ")"; break;
            case '{': opening = "{"; closing = "}"; break;
            case '\'': opening = "\'"; closing = "\'"; break;
            case '\"': opening = "\""; closing = "\""; break;
            default: return false; 
        }
        
        wrap_selection_or_insert_pair(opening, closing);
        return true;
    }

    private void wrap_selection_or_insert_pair(string op, string cl) {
        Gtk.TextIter start, end;

        // Начало транзакции — всё внутри будет одной операцией Undo
        buffer.begin_user_action();

        if (buffer.get_selection_bounds(out start, out end)) {
            // Кейс: Окружаем выделение

            // 1. Сохраняем символьные смещения (оффсеты) исходного выделения
            int orig_start_offset = start.get_offset();
            int orig_end_offset = end.get_offset();

            // 2. Вставляем открывающий символ (start сместится сам)
            buffer.insert(ref start, op, -1);

            // 3. Получаем свежий итератор для конца, так как старый 'end' мог стать невалидным
            // Смещение конца теперь сдвинулось ровно на длину открывающего символа (обычно +1)
            buffer.get_iter_at_offset(out end, orig_end_offset + op.char_count());
            
            // 4. Вставляем закрывающий символ
            buffer.insert(ref end, cl, -1);

            // 5. ВОЗВРАЩАЕМ ВЫДЕЛЕНИЕ: оно должно быть между старым текстом
            // Начало сдвинулось на длину 'op'
            // Конец тоже сдвинулся на длину 'op' (но не включает 'cl')
            Gtk.TextIter new_start, new_end;
            buffer.get_iter_at_offset(out new_start, orig_start_offset + op.char_count());
            buffer.get_iter_at_offset(out new_end, orig_end_offset + op.char_count());
            
            buffer.select_range(new_start, new_end);
        } else {
            // Кейс: Обычная вставка пары
            Gtk.TextIter iter;
            buffer.get_iter_at_mark(out iter, buffer.get_insert());
            buffer.insert(ref iter, op + cl, -1);
            
            // Возвращаем курсор назад на один символ
            iter.backward_char();
            buffer.place_cursor(iter);
        }

        buffer.end_user_action();
    }

    public void on_insert_text (Gtk.TextIter iter, string text, int len_bytes) {
        uint32 start_byte = get_byte_offset_safe (iter);
        uint32 start_row = (uint32) iter.get_line ();
        uint32 start_col = (uint32) iter.get_line_index (); // Байтовый индекс в строке

        uint32 lines_added = 0;
        uint32 last_line_bytes = 0;
        int last_nl_idx = -1;

        // Считаем перенос строк строго по байтам сырого массива UTF-8
        for (int i = 0; i < len_bytes; i++) {
            if (text[i] == '\n') {
                lines_added++;
                last_nl_idx = i;
            }
        }

        if (lines_added > 0) {
            // Длина последней строки в байтах от последнего \n до конца текста
            last_line_bytes = (uint32) (len_bytes - 1 - last_nl_idx);
        } else {
            // Если вставили внутри одной строки, длина конца — это просто len_bytes
            last_line_bytes = (uint32) len_bytes;
        }

        InputEdit edit = {};
        edit.start_byte = start_byte;
        edit.start_point = { start_row, start_col };
        
        // При вставке старый конец равен началу
        edit.old_end_byte = start_byte;
        edit.old_end_point = { start_row, start_col };

        // Новый конец — это математический сдвиг на основе добавленных строк и байт
        edit.new_end_byte = start_byte + (uint32) len_bytes;
        edit.new_end_point = Point () {
            row = start_row + lines_added,
            // Если добавились строки, колонка начнется с 0 + байты остатка.
            // Если вставка однострочная, колонка смещается на размер вставки.
            column = (lines_added > 0) ? last_line_bytes : start_col + last_line_bytes
        };

        this.tree.edit (edit);
    }

    public void on_delete_range (Gtk.TextIter start, Gtk.TextIter end) {
        uint32 start_byte = get_byte_offset_safe (start);
        uint32 old_end_byte = get_byte_offset_safe (end);

        InputEdit edit = {};
        // Где началось удаление
        edit.start_byte = start_byte;
        edit.start_point = { (uint32) start.get_line (), (uint32) start.get_line_index () };
        
        // Где заканчивался удаляемый фрагмент в старом дереве
        edit.old_end_byte = old_end_byte;
        edit.old_end_point = { (uint32) end.get_line (), (uint32) end.get_line_index () };
        
        // Новые координаты после удаления схлопнутся в точку старта
        edit.new_end_byte = start_byte;
        edit.new_end_point = edit.start_point;

        this.tree.edit (edit);
    }

    public void expand_selection () {
        if (tree == null)
            return;

        Gtk.TextIter start_sel, end_sel;
        // Получаем текущее выделение
        buffer.get_selection_bounds (out start_sel, out end_sel);

        // Начало буфера для расчета смещений
        Gtk.TextIter start_buf;
        buffer.get_start_iter (out start_buf);

        // Конвертируем итераторы в абсолютные байтовые смещения через длину среза
        uint32 start_byte = (uint32) buffer.get_slice (start_buf, start_sel, false).length;
        uint32 end_byte = (uint32) buffer.get_slice (start_buf, end_sel, false).length;

        // Ищем узел, который охватывает текущее выделение
        flush_changes ();
        TreeSitter.Node root = tree.root_node ();
        TreeSitter.Node node = root.named_descendant_for_byte_range (start_byte, end_byte);

        if (node.is_null ())return;

        if (node.start_byte () == start_byte && node.end_byte () == end_byte) {
            var parent = node.parent ();
            if (!parent.is_null ())node = parent;
        }

        // Сохраняем текущий диапазон в стек перед расширением
        TreeSitter.Range current_range = {
            { (uint32) start_sel.get_line (), (uint32) start_sel.get_line_index () },
            { (uint32) end_sel.get_line (), (uint32) end_sel.get_line_index () },
            start_byte,
            end_byte
        };

        selection_stack.offer_head (current_range);

        // Устанавливаем новое выделение
        Gtk.TextIter new_start, new_end;
        get_iters_from_ts_node (buffer, node, out new_start, out new_end);
        is_internal_selection_change = true;
        buffer.select_range (new_start, new_end);
        is_internal_selection_change = false;
    }

    public void shrink_selection () {
        if (selection_stack.is_empty)
            return;

        // Достаем последний сохраненный диапазон
        var last_range = selection_stack.poll ();

        if (last_range != null) {
            Gtk.TextIter s_iter, e_iter;

            // Используем твой рабочий метод для получения итераторов
            get_iters_from_ts_node_coords (last_range.start_point, last_range.end_point, out s_iter, out e_iter);

            // Устанавливаем выделение обратно
            is_internal_selection_change = true;
            buffer.select_range (s_iter, e_iter);
            is_internal_selection_change = false;
        }
    }

    private Gee.List<SourceNodeItem?> get_siblings_for_node (TreeSitter.Node parent_node) {
        var siblings = new Gee.ArrayList<SourceNodeItem?> ();
        if (parent_node.is_null ())return siblings;

        for (uint32 i = 0; i < parent_node.named_child_count (); i++) {
            var child = parent_node.named_child (i);
            if (is_container_node (child.type ())) {
                var name_node = find_name_node (child);
                if (name_node != null && !name_node.is_null ()) {
                    Gtk.TextIter s, e;
                    get_iters_from_ts_node (buffer, name_node, out s, out e);
                    var start_point = child.start_point ();
                    siblings.add (SourceNodeItem () {
                        name = buffer.get_text (s, e, false),
                        type = child.type (),
                        start_point = SourceNodePosition() {
                            row = start_point.row,
                            column = start_point.column
                        },
                    });
                }
            }
        }
        return siblings;
    }

    public Gee.List<SourceNodeItem?> get_breadcrumbs_at_cursor () {
        var result = new Gee.ArrayList<SourceNodeItem?> ();
        if (tree == null)return result;

        Gtk.TextIter insert_iter;
        buffer.get_iter_at_mark (out insert_iter, buffer.get_insert ());

        // Получаем абсолютное байтовое смещение (твой проверенный способ)
        Gtk.TextIter start_buf;
        buffer.get_start_iter (out start_buf);
        uint32 byte_offset = (uint32) buffer.get_slice (start_buf, insert_iter, false).length;

        // Ищем именованный узел под курсором
        TreeSitter.Node node = tree.root_node ().named_descendant_for_byte_range (byte_offset, byte_offset);

        // Поднимаемся вверх к корню
        while (!node.is_null ()) {
            // Используем абстрактный метод для проверки типа
            if (is_container_node (node.type ())) {
                TreeSitter.Node? name_node = find_name_node (node);
                if (name_node != null && !name_node.is_null ()) {
                    Gtk.TextIter s, e;
                    get_iters_from_ts_node (buffer, name_node, out s, out e);
                    // Получаем всех соседей этого узла (детей его родителя)
                    var siblings = get_siblings_for_node (node.parent ());
                    var start_point = node.start_point ();
                    result.insert (0, SourceNodeItem () {
                        name = buffer.get_text (s, e, false),
                        type = node.type (),
                        start_point = SourceNodePosition() {
                            row = start_point.row,
                            column = start_point.column
                        }, // Прыгаем к началу всего блока (fn/class)
                        siblings = siblings,
                    });
                }
            }
            node = node.parent ();
        }
        return result;
    }

    private TreeSitter.Node? find_name_node (TreeSitter.Node node) {
        string f_name = "name";
        TreeSitter.Node name_node = node.child_by_field_name (f_name, (uint32) f_name.length);
        if (!name_node.is_null ())return name_node;

        // Фолбэк: ищем любой идентификатор в начале узла
        for (uint32 i = 0; i < uint32.min (node.child_count (), 5); i++) {
            TreeSitter.Node child = node.child (i);
            if (child.type ().contains ("identifier"))return child;
        }
        return null;
    }

    private void update_breadcrumbs () {
        var new_crumbs = get_breadcrumbs_at_cursor ();
        if (last_crumbs != new_crumbs) {
            last_crumbs = new_crumbs;
            breadcrumbs_changed (last_crumbs);
        }
    }

    public Gee.List<SourceNodeItem?> get_full_outline () {
        var root = tree.root_node ();
        return collect_container_children (root);
    }

    private Gee.List<SourceNodeItem?> collect_container_children (TreeSitter.Node parent) {
        var list = new Gee.ArrayList<SourceNodeItem?> ();

        for (uint32 i = 0; i < parent.named_child_count (); i++) {
            var child = parent.named_child (i);

            if (is_container_node (child.type ())) {
                var name_node = find_name_node (child);
                if (name_node != null && !name_node.is_null ()) {
                    Gtk.TextIter s, e;
                    get_iters_from_ts_node (buffer, name_node, out s, out e);
                    var start_point = child.start_point ();
                    var item = SourceNodeItem () {
                        name = buffer.get_text (s, e, false),
                        type = child.type (),
                        start_point = SourceNodePosition() {
                            row = start_point.row,
                            column = start_point.column
                        },
                        children = collect_container_children (child),
                    };
                    list.add (item);
                } else {
                    // Если это контейнер, но у него нет имени (странно, но бывает),
                    // все равно ищем внутри него
                    list.add_all (collect_container_children (child));
                }
            } else {
                // КЛЮЧЕВОЙ МОМЕНТ:
                // Если текущий узел НЕ контейнер (например, блок if или namespace),
                // мы все равно должны заглянуть внутрь, так как там могут быть контейнеры.
                list.add_all (collect_container_children (child));
            }
        }
        return list;
    }

    ~BaseTreeSitterHighlighter () {
        // Явное зануление для вызова free_functions из VAPI
        this.parser = null;
        this.tree = null;
        this.query = null;
        this.cursor = null;
    }
}