using TreeSitter;

public struct TreeSitterNodeItem {
    public string name;
    public string type;
    public TreeSitter.Point start_point;
    public Gee.List<TreeSitterNodeItem?> siblings; // Добавляем список соседей
    public Gee.List<TreeSitterNodeItem?> children;
}

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

    protected BaseTreeSitterIndenter? ts_indenter;
    private bool _internal_change = false;
    private uint pending_indents = 0;

    // Оптимизированный кэш: [capture_index, theme_index]
    // theme_index: 1 - Light, 0 - Dark
    private Gtk.TextTag ? [, ] capture_tags;

    // Глобальный указатель на текущую тему (может обновляться из DocumentManager)
    private int current_theme_index = 0;

    // Таймер для Debounce
    private uint highlight_timeout_id = 0;
    private const uint DEBOUNCE_MS = 150;

    // Список структур Range из Tree-sitter для хранения истории
    private Gee.ArrayQueue<TreeSitter.Range?> selection_stack = new Gee.ArrayQueue<TreeSitter.Range?> ();
    private bool is_internal_selection_change = false;

    private Gee.List<TreeSitterNodeItem?> last_crumbs = null;
    public signal void breadcrumbs_changed (Gee.List<TreeSitterNodeItem?> crumbs);

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
        // 1. Сначала переходим строго по номеру строки
        buffer.get_iter_at_line (out iter, (int) position.row);

        // 2. БЕЗОПАСНАЯ УСТАНОВКА ИНДЕКСА
        // Вместо прямого set_line_index, проверяем длину строки
        int bytes_in_line = iter.get_bytes_in_line ();

        // Если Tree-sitter просит индекс за пределами текущей строки
        if ((int) position.column < bytes_in_line) {
            iter.set_line_index ((int) position.column);
        } else if ((int) position.column == bytes_in_line && bytes_in_line > 0) {
            // Мы в самом конце строки (возможно на \n)
            iter.set_line_index ((int) position.column);
        } else {
            // Если индекс совсем за пределами, значит этой части текста еще нет
            // или Tree-sitter запрашивает пустоту
            return null;
        }

        if (iter.is_end ())return null;

        Gtk.TextIter end = iter;
        // Захватываем текст до конца строки
        if (end.forward_to_line_end ()) {
            // Если не конец файла, захватываем символ переноса (\n)
            if (!end.is_end ()) {
                end.forward_char ();
            }
        } else {
            end.forward_to_end ();
        }

        string chunk = buffer.get_slice (iter, end, false);
        bytes_read = (uint32) chunk.length;

        return chunk;
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

        // Определяем язык
        unowned Language lang = get_ts_language ();
        this.parser.set_language (lang);
        // Загружаем Query
        load_query (lang);
        // Подготавливаем индексный мост сразу после загрузки Query
        prepare_capture_mapping ();

        this.ts_indenter = this.create_indenter ();
        if (ts_indenter != null) {
            view.auto_indent = false;
        }

        // Устанавливаем тему цвета и подписываемся на изменение схемы цветов
        set_color_theme ();
        this.buffer.notify["style-scheme"].connect_after (set_color_theme);

        // Подключаемся к низкоуровневым сигналам
        buffer.insert_text.connect (on_insert_text);
        buffer.delete_range.connect (on_delete_range);

        buffer.notify["cursor-position"].connect (() => {
            // Если позиция курсора изменилась не через наши методы expand/shrink — чистим стек
            if (!is_internal_selection_change) {
                selection_stack.clear ();
            }
        });

        buffer.notify["cursor-position"].connect (update_breadcrumbs);
    }

    // Абстрактные методы для реализации в подклассах (Vala, Cpp и т.д.)
    protected abstract unowned Language get_ts_language ();
    protected abstract string get_query_filename ();
    protected abstract string query_source ();

    // Абстрактный метод для фильтрации узлов Breadcrumbs
    protected abstract bool is_container_node (string node_type);

    // Виртуальный метод создания индентера
    public virtual BaseTreeSitterIndenter ? create_indenter () {
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

    private void on_buffer_changed () {
        if (highlight_timeout_id > 0) {
            Source.remove (highlight_timeout_id);
        }

        highlight_timeout_id = Timeout.add (DEBOUNCE_MS, () => {
            // run_highlighting ();
            sync_and_render ();
            highlight_timeout_id = 0;
            return Source.REMOVE;
        });
    }

    private void initial_rehighlight () {
        Gtk.TextIter start, end;
        buffer.get_bounds (out start, out end);

        this.tree = parser.parse (null, ts_input);

        update_breadcrumbs ();

        // Удаляем старые теги
        buffer.remove_all_tags (start, end);

        this.cursor = new QueryCursor ();
        cursor.exec (query, tree.root_node ());
        render_matches ();
    }

    private void sync_and_render () {
        // old_tree уже содержит правки от on_insert_text / on_delete_range
        unowned TreeSitter.Tree? old_tree = this.tree;
        var new_tree = parser.parse (old_tree, ts_input);
        update_breadcrumbs ();

        TreeSitter.Range[] changed_ranges = old_tree.get_changed_ranges (new_tree);
        this.tree = (owned) new_tree;
        this.cursor = new QueryCursor ();
        foreach (var range in changed_ranges) {
            Gtk.TextIter s, e;
            // Используем твой рабочий метод для получения итераторов
            get_iters_from_ts_node_coords (range.start_point, range.end_point, out s, out e);

            // Точечная очистка и перекраска
            buffer.remove_all_tags (s, e);

            cursor.set_byte_range (range.start_byte, range.end_byte);
            cursor.exec (query, tree.root_node ());
            render_matches ();
        }
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

    public void apply_indent (Gtk.TextIter iter, IndentInstruction instr, int indent_width) {
        var buffer = iter.get_buffer ();
        int current_offset = iter.get_offset ();

        // 1. Удаляем пробелы в конце ПРЕДЫДУЩЕЙ строки
        if (instr.trim_chars > 0) {
            Gtk.TextIter del_end = iter;
            del_end.backward_char (); // встали ПЕРЕД \n
            Gtk.TextIter del_start = del_end;
            for (int i = 0; i < instr.trim_chars; i++)del_start.backward_char ();

            this._internal_change = true;
            buffer.delete (ref del_start, ref del_end);
            this._internal_change = false;

            current_offset -= instr.trim_chars;
        }

        // 2. Формируем финальную строку отступа
        string padding = (instr.level_delta > 0) ? string.nfill (indent_width, ' ') : "";
        string final_indent = instr.base_indent + padding;

        // 3. Вставляем отступ в начало новой строки
        if (final_indent.length > 0) {
            Gtk.TextIter insert_pos;
            buffer.get_iter_at_offset (out insert_pos, current_offset);

            this._internal_change = true;
            buffer.insert (ref insert_pos, final_indent, (int) final_indent.length);
            this._internal_change = false;
        }
    }

    private void on_insert_text (Gtk.TextIter iter, string text, int len_bytes) {
        // 1. Фиксируем точку вставки (здесь она абсолютно стабильна)
        uint32 start_byte = get_byte_offset_safe (iter);
        uint32 start_row = (uint32) iter.get_line ();
        uint32 start_col = (uint32) iter.get_line_index ();

        // 2. Считаем статистику вставляемого текста
        uint32 lines_added;
        uint32 last_line_bytes;
        calculate_text_stats (text, out lines_added, out last_line_bytes);

        LoggerService.get_instance ().info ("CTS", "lines_added = %u --- last_line_bytes = %u".printf (lines_added, last_line_bytes));

        // 3. Формируем Edit
        InputEdit edit = {};
        edit.start_byte = start_byte;
        edit.start_point = { start_row, start_col };

        // При вставке "старый конец" совпадает с началом (мы ничего не удаляли)
        edit.old_end_byte = start_byte;
        edit.old_end_point = { start_row, start_col };

        // "Новый конец" — это математический результат вставки
        edit.new_end_byte = start_byte + (uint32) text.length;
        edit.new_end_point = Point () {
            row = start_row + lines_added,
            column = (lines_added > 0) ? last_line_bytes : start_col + last_line_bytes
        };

        tree.edit (edit);

        if (_internal_change)
            return;

        // В сигнале insert-text (ДО вставки)
        if (ts_indenter != null && text == "\n") {
            pending_indents++; // Увеличиваем счетчик задач

            int offset_for_idle = iter.get_offset () + 1;

            Idle.add (() => {
                if (pending_indents == 0)
                    return false;

                // А. СИНХРОНИЗАЦИЯ: Получаем актуальное дерево
                this.sync_and_render ();

                Gtk.TextIter fresh_iter;
                buffer.get_iter_at_offset (out fresh_iter, offset_for_idle);

                // 1. Анализируем
                var instr = ts_indenter.need_indent (this.tree, fresh_iter);

                // 2. Исполняем
                apply_indent (fresh_iter, instr, view.indent_width);

                //// Б. РАСЧЕТ: Вычисляем отступ
                // string suffix = ts_indenter.calculate_indent (this.tree, fresh_iter, view.indent_width);

                // if (suffix.length > 0) {
                // _internal_change = true;

                //// 2. СБРОС ТАЙМЕРА: Если мы сейчас вставим пробелы,
                //// старый запланированный таймер подсветки нам не нужен
                // if (highlight_timeout_id > 0) {
                // Source.remove (highlight_timeout_id);
                // highlight_timeout_id = 0;
                // }

                // buffer.insert (ref fresh_iter, suffix, (int) suffix.length);
                // _internal_change = false;
                // }

                pending_indents--; // Уменьшаем счетчик

                // В. ЗАПУСК: Планируем перекраску после всех манипуляций
                on_buffer_changed ();

                return false;
            });
        }

        // Если это не Enter, просто запускаем обычный дебаунс раскраски
        on_buffer_changed ();
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

    private void on_delete_range (Gtk.TextIter start, Gtk.TextIter end) {
        InputEdit edit = {};

        Gtk.TextIter start_buf;
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

        tree.edit (edit);

        // 2. Блокируем перекраску, если удаление инициировано индентером
        if (_internal_change)
            return;

        // После правки дерева запускаем отложенную перекраску (debounce)
        on_buffer_changed ();
    }

    public void expand_selection () {
        if (tree == null)return;

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
        if (selection_stack.is_empty)return;

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

    private Gee.List<TreeSitterNodeItem?> get_siblings_for_node (TreeSitter.Node parent_node) {
        var siblings = new Gee.ArrayList<TreeSitterNodeItem?> ();
        if (parent_node.is_null ())return siblings;

        for (uint32 i = 0; i < parent_node.named_child_count (); i++) {
            var child = parent_node.named_child (i);
            if (is_container_node (child.type ())) {
                var name_node = find_name_node (child);
                if (name_node != null && !name_node.is_null ()) {
                    Gtk.TextIter s, e;
                    get_iters_from_ts_node (buffer, name_node, out s, out e);
                    siblings.add (TreeSitterNodeItem () {
                        name = buffer.get_text (s, e, false),
                        type = child.type (),
                        start_point = child.start_point ()
                    });
                }
            }
        }
        return siblings;
    }

    public Gee.List<TreeSitterNodeItem?> get_breadcrumbs_at_cursor () {
        var result = new Gee.ArrayList<TreeSitterNodeItem?> ();
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
                    result.insert (0, TreeSitterNodeItem () {
                        name = buffer.get_text (s, e, false),
                        type = node.type (),
                        start_point = node.start_point (), // Прыгаем к началу всего блока (fn/class)
                        siblings = siblings
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

    public Gee.List<TreeSitterNodeItem?> get_full_outline () {
        var root = tree.root_node ();
        return collect_container_children (root);
    }

    private Gee.List<TreeSitterNodeItem?> collect_container_children (TreeSitter.Node parent) {
        var list = new Gee.ArrayList<TreeSitterNodeItem?> ();

        for (uint32 i = 0; i < parent.named_child_count (); i++) {
            var child = parent.named_child (i);

            if (is_container_node (child.type ())) {
                var name_node = find_name_node (child);
                if (name_node != null && !name_node.is_null ()) {
                    Gtk.TextIter s, e;
                    get_iters_from_ts_node (buffer, name_node, out s, out e);

                    var item = TreeSitterNodeItem () {
                        name = buffer.get_text (s, e, false),
                        type = child.type (),
                        start_point = child.start_point (),
                        // Рекурсивно ищем детей ТОЛЬКО внутри этого контейнера для иерархии
                        children = collect_container_children (child)
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