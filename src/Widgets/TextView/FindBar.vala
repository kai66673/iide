/*
*/

public class Iide.FindBar : Gtk.Box {
    private SourceView source_view;
    private Gtk.Entry search_entry;
    private Gtk.Label count_label;

    // Нативные поисковые структуры GtkSourceView 5
    private GtkSource.SearchSettings search_settings;
    private GtkSource.SearchContext search_context;

    // Кнопки настроек поиска
    private Gtk.ToggleButton case_btn;
    private Gtk.ToggleButton word_btn;

    // Сигнал, чтобы статус-бар знал, когда закрыть панель поиска по клавише Esc
    public signal void close_requested ();

    public FindBar (SourceView source_view) {
        Object (orientation: Gtk.Orientation.HORIZONTAL, spacing: 6);
        this.source_view = source_view;
        this.add_css_class ("editor-find-bar");

        // Инициализируем нативный поисковый движок
        var buffer = source_view.get_buffer () as GtkSource.Buffer;
        this.search_settings = new GtkSource.SearchSettings ();
        this.search_context = new GtkSource.SearchContext (buffer, this.search_settings);
        
        // Включаем автоматическую подсветку ВСЕХ найденных совпадений в коде
        this.search_context.highlight = true;

        // Поле ввода текста
        this.search_entry = new Gtk.Entry ();
        this.search_entry.placeholder_text = "Найти в файле...";
        this.search_entry.width_request = 200;
        this.search_entry.add_css_class ("search-entry");
        this.append (this.search_entry);

        // === ДОРАБОТКА №3: КНОПКИ НАСТРОЕК ПОИСКА ===
        // Учитывать регистр (Aa)
        this.case_btn = new Gtk.ToggleButton ();
        this.case_btn.icon_name = "format-text-capitalize-symbolic";
        this.case_btn.tooltip_text = "Учитывать регистр";
        this.case_btn.add_css_class ("flat");
        this.case_btn.toggled.connect (() => {
            this.search_settings.case_sensitive = this.case_btn.active;
            this.update_match_count ();
        });
        this.append (this.case_btn);

        // Слово целиком (W)
        this.word_btn = new Gtk.ToggleButton ();
        this.word_btn.icon_name = "text-fields-symbolic"; // В Adwaita часто используется для границ текста
        this.word_btn.tooltip_text = "Слово целиком";
        this.word_btn.add_css_class ("flat");
        this.word_btn.toggled.connect (() => {
            this.search_settings.at_word_boundaries = this.word_btn.active;
            this.update_match_count ();
        });
        this.append (this.word_btn);

        // Метка счетчика совпадений
        this.count_label = new Gtk.Label ("0 из 0");
        this.count_label.add_css_class ("dim-label");
        this.count_label.margin_end = 6;
        this.append (this.count_label);

        // Кнопка: Назад (Предыдущее совпадение)
        var prev_btn = new Gtk.Button.from_icon_name ("go-up-symbolic");
        prev_btn.tooltip_text = "Предыдущее совпадение (Shift+Enter)";
        prev_btn.clicked.connect (this.jump_to_previous);
        this.append (prev_btn);

        // Кнопка: Вперед (Следующее совпадение)
        var next_btn = new Gtk.Button.from_icon_name ("go-down-symbolic");
        next_btn.tooltip_text = "Следующее совпадение (Enter)";
        next_btn.clicked.connect (this.jump_to_next);
        this.append (next_btn);

        // === ОБРАБОТКА ДИНАМИЧЕСКОГО ПОИСКА ПРИ ВВОДЕ ===
        this.search_entry.changed.connect (() => {
            string text = this.search_entry.text;
            // Передаем текст в настройки, GtkSourceView мгновенно подсветит совпадения на экране!
            this.search_settings.search_text = text.length > 0 ? text : null;
            this.update_match_count ();
        });

        // Обработка клавиш Enter (Вперед) и Shift+Enter (Назад) внутри инпута
        this.search_entry.activate.connect (() => {
            this.jump_to_next ();
        });

        // Обработка Esc для закрытия панели поиска
        var key_ctrl = new Gtk.EventControllerKey ();
        key_ctrl.key_pressed.connect ((keyval, keycode, state) => {
            if (keyval == Gdk.Key.Escape) {
                this.close_requested ();
                return true;
            }
            // Перехватываем Shift+Enter внутри инпута для движения назад
            if (keyval == Gdk.Key.Return && (state & Gdk.ModifierType.SHIFT_MASK) != 0) {
                this.jump_to_previous ();
                return true;
            }
            return false;
        });
        this.search_entry.add_controller (key_ctrl);

        // Подписываемся на асинхронное уведомление от движка об изменении количества совпадений
        this.search_context.notify["occurrences-count"].connect (() => {
            this.update_match_count ();
        });
    }

    /**
     * УМНЫЙ ПЕРЕХВАТ ФОКУСА И ОБНОВЛЕНИЕ КОНТЕКСТА ПОИСКА
     * @param selected_text Текст, который был выделен в редакторе в момент нажатия Ctrl+F
     */
    public void grab_search_focus (string? selected_text) {
        this.search_entry.grab_focus ();
        
        // Если в редакторе было валидное однострочное выделение
        if (selected_text != null && selected_text.length > 0 && !selected_text.contains ("\n")) {
            this.search_entry.text = selected_text;
        }
        
        this.search_entry.select_region (0, -1); // Выделяем для возможности мгновенной перезаписи
    }

    /**
     * Деактивация поиска (вызывается при закрытии бара)
     */
    public void clear_search_context () {
        this.search_settings.search_text = null; // Отключаем подсветку в коде
    }

    private void jump_to_next () {
        var buffer = this.source_view.get_buffer ();
        Gtk.TextIter start_search_iter;
        
        Gtk.TextIter sel_start, sel_end;
        // Если сейчас уже выделено слово, мы начинаем поиск строго С КОНЦА этого выделения.
        // Это решает проблему бесконечного залипания на первом символе текущего слова!
        if (buffer.get_selection_bounds (out sel_start, out sel_end)) {
            start_search_iter = sel_end;
        } else {
            buffer.get_iter_at_mark (out start_search_iter, buffer.get_insert ());
        }

        Gtk.TextIter match_start, match_end;
        bool wrapped;

        if (this.search_context.forward (start_search_iter, out match_start, out match_end, out wrapped)) {
            buffer.select_range (match_start, match_end);
            this.source_view.scroll_to_iter (match_start, 0.0, false, 0.5, 0.5);
        }
    }

    private void jump_to_previous () {
        Gtk.TextIter cursor_iter;
        var buffer = this.source_view.get_buffer ();
        buffer.get_iter_at_mark (out cursor_iter, buffer.get_insert ());

        Gtk.TextIter match_start, match_end;
        bool wrapped;

        // Нативный асинхронный поиск назад относительно курсора
        if (this.search_context.backward (cursor_iter, out match_start, out match_end, out wrapped)) {
            buffer.select_range (match_start, match_end);
            this.source_view.scroll_to_iter (match_start, 0.0, false, 0.5, 0.5);
        }
    }

    private void update_match_count () {
        int total = this.search_context.occurrences_count;
        if (total <= 0 || this.search_entry.text.length == 0) {
            this.count_label.label = "0 из 0";
            return;
        }

        // Вычисляем, на каком по счету совпадении сейчас стоит курсор
        Gtk.TextIter cursor_iter;
        var buffer = this.source_view.get_buffer ();
        buffer.get_iter_at_mark (out cursor_iter, buffer.get_insert ());

        int current_position = this.search_context.get_occurrence_position (cursor_iter, cursor_iter);
        
        // Если get_occurrence_position вернул -1, значит мы между совпадениями, 
        // найдем позицию ближайшего следующего совпадения
        if (current_position <= 0) {
            Gtk.TextIter next_start, next_end;
            bool wrapped;
            if (this.search_context.forward (cursor_iter, out next_start, out next_end, out wrapped)) {
                current_position = this.search_context.get_occurrence_position (next_start, next_end);
            }
        }

        // Корректируем индекс для UI (get_occurrence_position возвращает 1-indexed или 0)
        int current_ui_idx = current_position > 0 ? current_position : 1;
        if (current_ui_idx > total) current_ui_idx = total;

        this.count_label.label = "%d из %d".printf (current_ui_idx, total);
    }
}

