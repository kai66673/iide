public class Iide.WordRange {
    public int line;
    public int start_column;
    public int end_column;

    public WordRange (int line, int start_column, int end_column) {
        this.line = line;
        this.start_column = start_column;
        this.end_column = end_column;
    }

    public bool is_equal (WordRange? other) {
        if (other == null) {
            return false;
        }
        return line == other.line && start_column == other.start_column && end_column == other.end_column;
    }
}

public class Iide.LspTooltipWidget : Gtk.Box {
    private Gtk.Label label;
    private Gtk.Spinner spinner;

    public LspTooltipWidget () {
        Object (
                orientation: Gtk.Orientation.HORIZONTAL,
                spacing: 6,
                margin_top: 8,
                margin_bottom: 8,
                margin_start: 8,
                margin_end: 8
        );

        spinner = new Gtk.Spinner ();
        label = new Gtk.Label ("Загрузка...");
        label.use_markup = true;
        label.wrap = true;
        label.max_width_chars = 60;

        append (spinner);
        append (label);
        spinner.start ();
    }

    public void update_text (string? text, bool show_spinner) {
        if (show_spinner) {
            spinner.start ();
            spinner.show ();
        } else {
            spinner.stop ();
            spinner.hide ();
        }

        if (text != null && text != "") {
            label.set_markup (text);
        } else {
            label.set_text ("Нет информации");
        }
    }
}

public class Iide.SourceView : GtkSource.View {
    public weak WindowSession session;
    private weak LoggerService logger;

    public string uri { get; private set; }
    private Iide.TreeSitterManager ts_manager;
    public Iide.LineNumbersGutter line_numbers_gutter;
    public GutterMarkRenderer mark_renderer;
    public TreeSitterFoldingGutter folding_gutter;
    private Gtk.TextIter? pending_scroll_iter = null;
    public Gee.HashMap<string, Gee.ArrayList<LspDiagnosticsMark>> lsp_marks =
        new Gee.HashMap<string, Gee.ArrayList<LspDiagnosticsMark>> ();

    private WordRange? last_hover_range = null;
    private bool suppress_lsp_echo = false;
    private LspTooltipWidget tooltip_widget;
    private string tooltip_separator = "────────────────────────────────────────";

    public LspDocumentClient lsp_document_client;
    public SourceDocument document;

    private int last_line = -1;
    private NavigationHistoryService history;

    private EditorOverlayLayer? overlay = null;
    private Gtk.Widget? folding_preview_widget = null;
    private int last_hovered_line = -1;
    private int line_number_symbols_count = 1;

    private CodeActionsPopup? code_actions_popup = null;
    private RenamePreviewDialog? rename_preview_dialog = null;

    // Отложенные правки переименования для файлов, которые ещё не открыты


    public signal void breadcrumbs_changed (Gee.List<SourceNodeItem?> crumbs);
    public signal void full_ts_rehighlight_requested ();

    public SourceView (WindowSession session, string uri, GtkSource.Buffer buffer) {
        Object (buffer : buffer);
        this.session = session;
        this.logger = session.logger_service;
        this.uri = uri;
        this.ts_manager = new TreeSitterManager ();
        this.history = this.session.navigation_history_service;

        this.tooltip_widget = new LspTooltipWidget ();

        // LSP-complete
        var completion = get_completion ();
        completion.select_on_show = true;
        completion.show_icons = true;
        completion.page_size = 18;
        completion.remember_info_visibility = false;
        var provider = new LspCompletionProvider (this);
        completion.add_provider (provider);

        // Build extra menu for context menu
        var zoom_section = new GLib.Menu ();
        zoom_section.append (_("Zoom In"), "app.zoom-in");
        zoom_section.append (_("Zoom Out"), "app.zoom-out");
        zoom_section.append (_("Reset Zoom"), "app.zoom-reset");

        var view_section = new GLib.Menu ();
        view_section.append (_("Minimap"), "app.show-minimap");
        view_section.append (_("Line Numbers"), "app.show-line-numbers");
        view_section.append (_("Diagnostics"), "app.show-diagnostics-marks");
        view_section.append (_("Folding"), "app.show-folding-gutter");
        view_section.append (_("Format"), "app.format");

        var extra_menu = new GLib.Menu ();
        extra_menu.append_section (null, zoom_section);
        extra_menu.append_section (null, view_section);
        this.extra_menu = extra_menu;

        var settings = Iide.SettingsService.get_instance ();

        highlight_current_line = settings.highlight_current_line;
        auto_indent = settings.auto_indent;
        indent_on_tab = true;
        
        // Marks gutter
        set_show_line_marks (false);
        var left_gutter = get_gutter (Gtk.TextWindowType.LEFT);
        left_gutter.visible = true;

        var line_numbers = this.buffer.get_line_count();
        this.line_number_symbols_count = line_numbers.to_string ().length;
        show_line_numbers = false;
        this.line_numbers_gutter = new Iide.LineNumbersGutter (this.session);
        this.line_numbers_gutter.update_initial_width (
            this.line_number_symbols_count,
            FontSizeHelper.get_size_for_zoom_level (settings.editor_font_size)
        );
        left_gutter.insert (this.line_numbers_gutter, 0); // Вес 0 — самая левая позиция
        line_numbers_gutter.visible = settings.show_line_numbers;
        this.buffer.changed.connect(() => {
            var new_line_numbers = this.buffer.get_line_count();
            var new_line_number_symbols_count = new_line_numbers.to_string ().length;
            if (new_line_number_symbols_count != this.line_number_symbols_count) {
                this.line_number_symbols_count = new_line_number_symbols_count;
                this.line_numbers_gutter.update_initial_width (
                    this.line_number_symbols_count,
                    FontSizeHelper.get_size_for_zoom_level (settings.editor_font_size)
                );
            }
        });

        mark_renderer = new GutterMarkRenderer ();
        mark_renderer.set_icons_size (FontSizeHelper.get_size_for_zoom_level (settings.editor_font_size));
        left_gutter.insert (mark_renderer, 10);

        this.folding_gutter = new TreeSitterFoldingGutter ();
        this.folding_gutter.set_icons_size (FontSizeHelper.get_size_for_zoom_level (settings.editor_font_size));
        left_gutter.insert (this.folding_gutter, 20);

        LspDiagnosticsMark.set_mark_attributes (this);
        
        var bp_attrs = new GtkSource.MarkAttributes ();
        var bp_bg = Gdk.RGBA ();
        bp_bg.parse ("rgba(181, 18, 42, 0.67)");
        bp_attrs.set_background (bp_bg);

        // 3. Регистрируем эти графические атрибуты для нашей категории маркеров!
        this.set_mark_attributes ("active-debug-line", bp_attrs, 100); // 100 — приоритет отрисовки поверх закладок

        // Connect to settings changes to apply to all open documents
        settings.editor_setting_changed.connect ((key) => {
            switch (key) {
                case "show-line-numbers" :
                    line_numbers_gutter.visible = settings.show_line_numbers;
                    break;
                case "show-diagnostics-marks":
                    mark_renderer.visible = settings.show_diagnostics_marks;
                    break;
                case "show-folding-gutter":
                    folding_gutter.visible = settings.show_folding_gutter;
                    break;
                case "highlight-current-line" :
                    highlight_current_line = settings.highlight_current_line;
                    break;
                case "auto-indent":
                    auto_indent = settings.auto_indent;
                    break;
            }
        });

        // SpaceDrawer
        var space_drawer = get_space_drawer ();

        // 2. Устанавливаем типы отображаемых символов
        space_drawer.set_enable_matrix (true);
        space_drawer.set_types_for_locations (
            GtkSource.SpaceLocationFlags.ALL,
            GtkSource.SpaceTypeFlags.NONE
        );
        space_drawer.set_types_for_locations (
            GtkSource.SpaceLocationFlags.LEADING | GtkSource.SpaceLocationFlags.TRAILING,
            GtkSource.SpaceTypeFlags.SPACE | GtkSource.SpaceTypeFlags.TAB
        );

        // LSP-tooltips
        has_tooltip = true;
        query_tooltip.connect (on_query_tooltip);

        // Control-click controller (goto definition)
        var click_gest = new Gtk.GestureClick ();
        click_gest.set_button (1);
        click_gest.released.connect (on_click_released);
        add_controller (click_gest);

        buffer.set_modified (false);

        // 1. Триггер по фокусу
        var focus_controller = new Gtk.EventControllerFocus ();
        focus_controller.enter.connect (() => {
            // При получении фокуса сохраняем текущую позицию
            handle_navigation_trigger (false);
        });
        add_controller (focus_controller);

        // 2. Триггер по перемещению курсора
        this.buffer.notify["cursor-position"].connect (() => {
            handle_navigation_trigger (true);
        });

        create_document ();

        var motion_ctrl = new Gtk.EventControllerMotion ();
        motion_ctrl.motion.connect (this.on_textview_motion);
        this.add_controller (motion_ctrl);

        foreach (var mark_service in this.session.marks_service) {
            mark_service.apply_marks_to_buffer (this.uri, this.buffer);
        }
    }

    public override bool grab_focus () {
        bool result = base.grab_focus();
        this.session.document_manager.add_document_to_mru_history (this);
        return result;
    }

    private void on_textview_motion (double x, double y) {
        if (this.overlay == null) return;

        var indicators = this.overlay.get_visible_indicators ();
        // 1. Ищем попадание в индикатор
        ClickableIndicator? hovered_indicator = null;
        foreach (var indicator in indicators) {
            var rect = indicator.rect;
            if (x >= rect.x && x <= (rect.x + rect.width) &&
                y >= rect.y && y <= (rect.y + rect.height)) {
                hovered_indicator = indicator;
                break;
            }
        }

        // ЗДЕСЬ ЕДИНСТВЕННОЕ МЕСТО, ГДЕ МЫ ИМЕЕМ ПРАВО ЗАКРЫТЬ ОКНО:
        // Только если мышь физически ушла с прямоугольника плашки!
        if (hovered_indicator == null) {
            this.hide_folding_preview ();
            return;
        }

        // Если поповер уже открыт для этой строки — ЗАПРЕЩАЕМ любые дальнейшие проверки 
        // и деструкции. Просто выходим. Это железобетонно защитит окно от закрытия.
        if (this.last_hovered_line == hovered_indicator.start_line && (this.folding_preview_widget != null)) {
            return; 
        }

        // Только если это ПЕРВЫЙ вход на новую строку — собираем данные и строим окно:
        var doc = this.document as Iide.TreeSitterDocument;
        if (doc == null || doc.ts_highlighter == null) return;

        var ts_blocks = doc.ts_highlighter.get_cached_indent_blocks ();
        Iide.IndentBlock? target_block = null;
        foreach (var block in ts_blocks) {
            if (block.start_line == hovered_indicator.start_line) {
                target_block = block;
                break;
            }
        }

        // Если при первом наведении кэш пуст — тихо выходим БЕЗ вызова hide
        if (target_block == null) return;

        var folding_gutter = this.folding_gutter;
        if (!folding_gutter.is_line_collapsed_by_number (target_block.start_line)) return;
        
        var buffer = this.get_buffer ();
        Gtk.TextIter start_iter, end_iter;
        buffer.get_iter_at_line (out start_iter, target_block.start_line + 1);
        buffer.get_iter_at_line (out end_iter, target_block.end_line + 1);

        // Фиксируем строку ДО создания виджета
        this.last_hovered_line = hovered_indicator.start_line;

        // Очищаем предыдущее окно, если оно висит
        if (this.folding_preview_widget != null) {
            this.hide_folding_preview ();
        }

        // ===================================================================
        // Создаем preview
        // ===================================================================
        
        // 1. Создаем изолированный буфер для подсказки (обязательно GtkSource.Buffer)
        var style_service = StyleService.get_instance ();
        var preview_buffer = new GtkSource.Buffer (style_service.shared_table);
        
        // Синхронизируем язык и цветовую схему
        var main_source_buffer = buffer as GtkSource.Buffer;
        if (main_source_buffer != null) {
            preview_buffer.set_style_scheme (main_source_buffer.get_style_scheme ());
        }

        // 2. Ставим итератор на начало нового буфера превью
        Gtk.TextIter preview_start;
        preview_buffer.get_start_iter (out preview_start);

        // 3. АТОМАРНО КОПИРУЕМ ДИАПАЗОН ТЕКСТА И ВСЕ ПРИМЕНЕННЫЕ ТЕГИ
        preview_buffer.insert_range (ref preview_start, start_iter, end_iter);
        
        // ===================================================================
        // КРИТИЧЕСКОЕ ИСПРАВЛЕНИЕ: Убираем невидимость с текста превью!
        // ===================================================================
        Gtk.TextIter p_start, p_end;
        preview_buffer.get_bounds (out p_start, out p_end);
        preview_buffer.remove_tag (style_service.folding_tag, p_start, p_end);
        // ===================================================================

        // 4. УМНОЕ ОГРАНИЧЕНИЕ СТРОК
        int max_lines = 90;
        if (preview_buffer.get_line_count () > max_lines) {
            Gtk.TextIter cut_start, cut_end;
            preview_buffer.get_iter_at_line (out cut_start, max_lines);
            preview_buffer.get_end_iter (out cut_end);
            
            preview_buffer.delete (ref cut_start, ref cut_end);
            preview_buffer.insert (ref cut_start, "\n   ...", -1);
        }

        // 1. Создаем наше кастомное текстовое превью
        var preview_view = new PreviewSourceView.with_buffer (preview_buffer, this);
        
        // 2. Оборачиваем его в ScrolledWindow, чтобы текст внутри аккуратно скроллился, 
        // если он не влезает в отведенную высоту
        var scrolled = new Gtk.ScrolledWindow ();
        scrolled.set_child (preview_view);
        scrolled.hscrollbar_policy = Gtk.PolicyType.NEVER;   // Горизонтальный скролл не нужен (включен wrap_mode)
        scrolled.vscrollbar_policy = Gtk.PolicyType.AUTOMATIC; // Вертикальный появится только при необходимости

        // 3. Создаем внешнюю рамку со стилями
        var frame = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
        frame.append (scrolled);
        frame.add_css_class ("folding-preview-floating-window");

        // === РАСЧЕТ ДИНАМИЧЕСКИХ ОГРАНИЧЕНИЙ ВЫСОТЫ ===
        int editor_height = this.get_height (); // Полная видимая высота текстового редактора
        int target_y = (int) hovered_indicator.rect.y + (int) hovered_indicator.rect.height + 4;
        
        // Вычисляем, сколько пикселей осталось от плашки "..." до нижнего края редактора
        int available_height = editor_height - target_y - 12; // 12px — безопасный отступ снизу
        
        // Желаемая высота по умолчанию — 340 пикселей (как вы и настраивали).
        // Но если до края экрана осталось меньше места, мы принудительно зажимаем высоту до доступной.
        int final_height = int.min (1200, available_height);

        // Если final_height получился слишком маленьким (например, строка в самом низу экрана),
        // можно перекинуть тултип НАВЕРХ (отобразить НАД строкой кода):
        if (final_height < 100) {
            final_height = int.min (1200, (int) hovered_indicator.rect.y - 12);
            // Пересчитываем Y, чтобы окно встало ровно НАД строкой кода
            target_y = (int) hovered_indicator.rect.y - final_height - 4;
        }

        // Жестко выставляем размеры контейнера
        frame.set_size_request (-1, final_height);

        this.folding_preview_widget = frame;

        // 4. ДОБАВЛЯЕМ В КОНТЕЙНЕР ОВЕРЛЕЯ
        var overlay_container = this.overlay.parent as Gtk.Overlay ?? this.parent as Gtk.Overlay;

        if (overlay_container != null) {
            overlay_container.add_overlay (this.folding_preview_widget);

            int gutter_width = 0;
            var left_gutter = this.get_gutter (Gtk.TextWindowType.LEFT);
            if (left_gutter != null) {
                gutter_width = left_gutter.get_width ();
            }

            // Позиционируем
            this.folding_preview_widget.margin_start = gutter_width;
            this.folding_preview_widget.margin_top = target_y;

            this.folding_preview_widget.halign = Gtk.Align.START;
            this.folding_preview_widget.valign = Gtk.Align.START;

            this.folding_preview_widget.queue_resize ();
            overlay_container.queue_allocate ();
        }
    }

    public void hide_folding_preview () {
        if (this.folding_preview_widget != null) {
            var overlay_container = this.overlay.parent as Gtk.Overlay ?? this.parent as Gtk.Overlay;
            if (overlay_container != null) {
                overlay_container.remove_overlay (this.folding_preview_widget);
            }
            this.folding_preview_widget = null;
            this.last_hovered_line = -1;
        }
    }


    public void set_overlay(EditorOverlayLayer overlay) {
        this.overlay = overlay;
    }
    
    private void create_document() {
        detect_language ();
        var ts_highlighter = ts_manager.get_ts_highlighter (this);
        if (ts_highlighter != null) {
            this.document = new TreeSitterDocument(this, ts_highlighter);
                ts_highlighter.folding_structure_updated.connect ((blocks) => {
                // Передаем актуальный список блоков прямиком в наш Gutter renderer
                this.folding_gutter.update_blocks_data (blocks);
            });
            this.folding_gutter.update_blocks_data (ts_highlighter.get_cached_indent_blocks ());
            this.full_ts_rehighlight_requested.connect (ts_highlighter.force_full_reparse);
        } else {
            this.document = new SourceDocument (this);
            this.folding_gutter.visible = false;
            this.mark_renderer.visible = false;
        }

        this.lsp_document_client = new LspDocumentClient (this, this.session.logger_service);
        this.document.document_changed.connect(this.on_lsp_document_changed);
        this.document.breadcrumbs_changed.connect ((crumbs) => {
            this.breadcrumbs_changed(crumbs);
        });
    }

    /**
     * Промежуточный обработчик изменений буфера.
     *
     * Во время применения LSP-правок (rename/code actions/auto-imports)
     * не отправляем инкрементальные диффы серверам: они уже применили эти
     * правки у себя. Синхронизация выполняется после через force_full_sync.
     */
    private void on_lsp_document_changed (PendingChange change) {
        if (this.suppress_lsp_echo)
            return;
        this.lsp_document_client.add_change (change);
    }

    public void expand_selection() {
        this.document.expand_selection ();
    }

    public void shrink_selection() {
        this.document.shrink_selection ();
    }

    public Gee.List<SourceNodeItem?> get_full_outline () {
        return this.document.get_full_outline ();
    }

    public async void lsp_sync_changes_async () {
        yield this.lsp_document_client.flush_changes_async ();
    }

    private void handle_navigation_trigger (bool check_distance) {
        Gtk.TextIter iter;
        this.buffer.get_iter_at_mark (out iter, this.buffer.get_insert ());
        int current_line = iter.get_line ();

        if (!check_distance || (last_line == -1 || (current_line - last_line).abs () > 10)) {
            save_current_point (iter);
        }

        last_line = current_line;
    }

    private void save_current_point (Gtk.TextIter iter) {
        var file = File.new_for_uri (uri);
        if (file != null) {
            history.push_point (file, iter.get_line (), iter.get_line_offset ());
        }
    }

    public GtkSource.Language? language {
        set {
            ((GtkSource.Buffer) buffer).language = value;
        }
        get {
            return ((GtkSource.Buffer) buffer).language;
        }
    }

    public void detect_language () {
        var manager = GtkSource.LanguageManager.get_default ();
        var file = GLib.File.new_for_uri (uri);

        string mime_type = mime_type_for_file (file);
        message ("MIME: _ " + mime_type);

        language = manager.guess_language (file.get_path (), mime_type);

        // Fake file type detection
        // "Not all files are equal"
        if (file.get_basename () == "CMakeLists.txt") {
            language = manager.get_language ("cmake");
        }
    }

    private static bool is_identifier_char (unichar c) {
        return c.isalnum () || c == '_';
    }

    public WordRange ? get_word_range_under_cursor (Gtk.TextIter cursor_iter) {
        // 1. Нюанс: Если курсор на пробеле, разделителе или переносе строки, слова под ним нет.
        // Важно: используем собственные границы идентификатора (буквы/цифры/_),
        // а не GtkTextIter.starts_word/ends_word, которые режут идентификаторы по '_'.
        if (!is_identifier_char (cursor_iter.get_char ())) {
            return null;
        }

        var buffer = this.get_buffer ();

        // 2. Ищем начало слова: идём назад, пока перед курсором стоят символы идентификатора
        Gtk.TextIter start_iter = cursor_iter;
        while (start_iter.backward_char ()) {
            if (!is_identifier_char (start_iter.get_char ())) {
                start_iter.forward_char ();
                break;
            }
        }

        // 3. Ищем конец слова (исключающий): идём вперёд от курсора
        Gtk.TextIter end_iter = cursor_iter;
        while (is_identifier_char (end_iter.get_char ())) {
            if (!end_iter.forward_char ()) {
                // Символ находится в самом конце буфера — конец диапазона равен концу буфера
                buffer.get_end_iter (out end_iter);
                break;
            }
        }

        return new WordRange (cursor_iter.get_line (), start_iter.get_line_offset (), end_iter.get_line_offset ());
    }

    private bool on_lsp_diagnostics_tooltip (GLib.SList<weak GtkSource.Mark> marks, Gtk.Tooltip tooltip) {
        var sb = new StringBuilder ();

        foreach (var mark in marks) {
            var lsp_mark = mark as LspDiagnosticsMark;
            if (lsp_mark == null) {
                continue;
            }

            string icon;
            string header_color;

            switch (lsp_mark.severity) {
            case 1 :
                icon = "❌";
                header_color = "#F44336"; // Красный
                break;
            case 2 :
                icon = "⚠️";
                header_color = "#FF9800"; // Оранжевый
                break;
            case 3:
            case 4:
                icon = "ℹ️";
                header_color = "#2196F3"; // Синий
                break;
            default:
                icon = "❌";
                header_color = "#F44336"; // Красный
                break;
            }

            if (sb.len > 0) {
                sb.append ("\n" + tooltip_separator + "\n");
            }

            // Заголовок и основное сообщение
            sb.append_printf ("%s <span font_weight='bold' foreground='%s'>%s (%s)</span>\n",
                              icon, header_color, lsp_mark.category.up (), lsp_mark.server_name);
            sb.append_printf ("<span>%s</span>", GLib.Markup.escape_text (lsp_mark.diagnostic_message));
        }

        if (sb.len > 0) {
            tooltip_widget.update_text (sb.str, false);
            tooltip.set_custom (tooltip_widget);
            return true;
        }

        return false;
    }

    private bool on_lsp_hover_tooltip (Gtk.TextIter iter, Gtk.Tooltip tooltip) {
        WordRange? word_range = get_word_range_under_cursor (iter);
        if (word_range == null) {
            last_hover_range = null;
            return false;
        }

        tooltip.set_custom (tooltip_widget);

        // Проверяем, не тот же ли эти 100мс назад
        if (word_range.is_equal (last_hover_range)) {
            return true;
        }
        tooltip_widget.update_text ("Loading...", true);
        last_hover_range = word_range;

        fetch_lsp_hover_async.begin (word_range.line, word_range.start_column + 1);

        return true;
    }

    private bool on_query_tooltip (int x, int y, bool keyboard_mode, Gtk.Tooltip tooltip) {
        // LSP-диагностика...
        Gtk.TextIter iter;

        // Преобразуем координаты окна в координаты буфера
        int buffer_x, buffer_y;
        window_to_buffer_coords (Gtk.TextWindowType.WIDGET, x, y, out buffer_x, out buffer_y);

        // Получаем итератор в месте курсора мыши
        if (!get_iter_at_location (out iter, buffer_x, buffer_y)) {
            return false;
        }

        // Ищем маркеры в этой строке (по категории "error")
        var buffer = (GtkSource.Buffer) buffer;
        var marks = buffer.get_source_marks_at_line (iter.get_line (), null);

        if (marks.length () > 0) {
            return on_lsp_diagnostics_tooltip (marks, tooltip);
        }

        // LSP-hover...
        return on_lsp_hover_tooltip (iter, tooltip);
    }

    private async void fetch_lsp_hover_async (int line, int col) {
        string? markdown = yield this.lsp_document_client.request_hover (uri, line, col);
        tooltip_widget.update_text (markdown, false);
    }

    private void on_click_released (Gtk.GestureClick gesture, int n_press, double x, double y) {
        // Получаем состояние модификаторов через основной контроллер
        var modifiers = gesture.get_current_event_state ();

        if ((modifiers & Gdk.ModifierType.CONTROL_MASK) != 0) {
            Gtk.TextIter iter;
            // В GTK4 координаты в сигнале уже относительны виджета
            // Переводим их в координаты буфера (с учетом прокрутки)
            int buf_x, buf_y;
            window_to_buffer_coords (Gtk.TextWindowType.WIDGET, (int) x, (int) y, out buf_x, out buf_y);

            if (get_iter_at_location (out iter, buf_x, buf_y)) {
                get_buffer ().place_cursor (iter);

                // Запускаем асинхронный переход
                this.lsp_document_client.flush_changes ();
                handle_ctrl_click_async.begin (iter.get_line (), iter.get_line_offset ());
            }
        }
    }

    private async void handle_ctrl_click_async (int line, int col) {
        Gee.ArrayList<LspLocation>? locations = null;
        try {
            locations = yield lsp_document_client.request_definition (uri, line, col);
        } catch (GLib.Error e) {
            logger.error ("LSP", "Failed to request defintion.");
            return;
        }

        if (locations == null || locations.size == 0) {
            logger.warning ("LSP", "No locations found for goto definition");
            return;
        }

        var loc = locations.get (0);
        if (this.uri == loc.uri) {
            this.select_and_scroll (loc.start_line, loc.start_column, loc.end_column, false);
        } else {
            session.document_manager.open_document_with_selection
                (File.new_for_uri (loc.uri), loc.start_line, loc.start_column, loc.end_column, null);
        }
    }

    public void select_and_scroll (int line, int start_col, int end_col, bool is_new) {
        if (line >= buffer.get_line_count ()) {
            return;
        }

        Gtk.TextIter start_iter;
        buffer.get_iter_at_line_offset (out start_iter, line, start_col);

        Gtk.TextIter end_iter;
        buffer.get_iter_at_line_offset (out end_iter, line, end_col);

        buffer.place_cursor (start_iter);
        buffer.select_range (start_iter, end_iter);
        scroll_to_iter (start_iter, 0.0, true, 0.5, 0.5);
        pending_scroll_iter = null;
        if (is_new) {
            pending_scroll_iter = start_iter;
        }
    }

    public override void size_allocate (int width, int height, int baseline) {
        base.size_allocate (width, height, baseline);
        if (pending_scroll_iter != null) {
            scroll_to_iter (pending_scroll_iter, 0.0, true, 0.5, 0.5);
            pending_scroll_iter = null;
        }
    }

    public void goto (int line, int column, bool save_to_navigation_history = true) {
        Gtk.TextIter iter;
        buffer.get_iter_at_line (out iter, line);
        iter.set_line_index (column);

        buffer.place_cursor (iter);
        scroll_to_iter (iter, 0.1, false, 0, 0.5);
        grab_focus ();
    }

    public void toggle_mark_on_current_line (TextLineMarkService mark_service) {
        var source_buffer = this.get_buffer () as GtkSource.Buffer;
        if (source_buffer == null)
            return;

        var marks_category = mark_service.category;

        // Получаем итератор текущей строки (где стоит курсор)
        Gtk.TextIter cursor_iter;
        source_buffer.get_iter_at_mark (out cursor_iter, source_buffer.get_insert ());
        int current_line = cursor_iter.get_line ();

        // Проверяем, есть ли уже закладки на этой строке
        var existing_marks = source_buffer.get_source_marks_at_line (current_line, marks_category);

        if (existing_marks != null && existing_marks.length () > 0) {
            // Если маркер уже есть — удаляем его со строки, снимая закладку [INDEX]
            foreach (var mark in existing_marks) {
                source_buffer.delete_mark (mark);
            }
            logger.info (
                "MRK", "Deleted GtkSource.Mark '%s' from line %d".printf (
                    marks_category, current_line + 1
                )
            );
        } else {
            // Если маркера нет — ставим его строго на начало строки [INDEX]
            Gtk.TextIter line_start_iter;
            source_buffer.get_iter_at_line (out line_start_iter, current_line);
            
            // Создаем новый SourceMark. 
            source_buffer.create_source_mark (null, marks_category, line_start_iter);
            logger.info (
                "MRK", "Created GtkSource.Mark '%s' on line %d".printf (
                    marks_category, current_line + 1
                )
            );
        }

        // Заставляем панель номеров строк мгновенно перерисоваться
        this.line_numbers_gutter.queue_draw ();

        BookmarksNavigator.get_instance().document_bookmarks_changed (this.uri, this.buffer);
    }

    /**
     * Собрать все сырые JSON-объекты диагностик LSP для указанной строки.
     * @return Массив Json.Array, готовый для отправки в request_code_actions, или null, если ошибок нет.
     */
    public Json.Array? collect_raw_diagnostics_for_line (int line_number) {
        var source_buffer = this.get_buffer () as GtkSource.Buffer;
        if (source_buffer == null) return null;

        // Ищем маркеры во всех трёх ваших категориях
        var diagnostics_array = new Json.Array ();

        var marks = source_buffer.get_source_marks_at_line (line_number, null);
        foreach (var mark in marks) {
            var lsp_mark = mark as LspDiagnosticsMark;
            if (lsp_mark == null) {
                continue;
            }
            if (lsp_mark.raw_json != null) {
                var node = new Json.Node (Json.NodeType.OBJECT);
                node.set_object (lsp_mark.raw_json);
                
                // Добавляем глубокую копию объекта в итоговый массив [INDEX]
                diagnostics_array.add_element (node.copy ());
            }
        }

        // Если на строке действительно нашлись ошибки — возвращаем массив, иначе null [INDEX]
        return diagnostics_array.get_length () > 0 ? diagnostics_array : null;
    }

    /**
     * Атомарно применить массив текстовых правок LSP к текущему буферу
     */
    public void apply_lsp_text_edits (Gee.ArrayList<Iide.LspTextEdit> edits) {
        var buffer = this.get_buffer ();
        if (buffer == null || edits.size == 0) return;

        // Сортируем правки по убыванию строк (снизу вверх файла), 
        // чтобы вставки не сдвигали координаты последующих правок!
        edits.sort ((a, b) => {
            if (b.start_line != a.start_line) {
                return b.start_line - a.start_line;
            }
            return b.start_char - a.start_char;
        });

        // Оборачиваем всю замену в единый Undo-блок [INDEX]
        buffer.begin_user_action ();

        // Подавляем эхо инкрементальных диффов: сервер уже применил эти правки
        // у себя, повторная отправка привела бы к двойному применению.
        this.suppress_lsp_echo = true;

        foreach (var edit in edits) {
            logger.debug ("LCA", "apply edit: [%d:%d]-[%d:%d] newText='%s'".printf (
                edit.start_line, edit.start_char, edit.end_line, edit.end_char, edit.new_text
            ));

            Gtk.TextIter start_iter, end_iter;
            buffer.get_iter_at_line_index (out start_iter, edit.start_line, edit.start_char);
            buffer.get_iter_at_line_index (out end_iter, edit.end_line, edit.end_char);

            // Если диапазон не пустой — это замена или удаление, стираем старый текст [INDEX]
            if (!start_iter.equal (end_iter)) {
                buffer.delete (ref start_iter, ref end_iter);
            }

            // Вставляем новый текст (например, "import os\n") [INDEX]
            if (edit.new_text.length > 0) {
                buffer.insert (ref start_iter, edit.new_text, -1);
            }
        }

        buffer.end_user_action ();
        this.suppress_lsp_echo = false;

        // Приводим состояние серверов в точное соответствие с буфером
        // (полный текст, идемпотентно для любого типа синхронизации).
        this.lsp_document_client.force_full_sync ();

        logger.info ("LCA", "Successfully applied %d text edits to buffer.".printf (edits.size));

        this.full_ts_rehighlight_requested ();
    }

    private void render_code_actions_popover (Gtk.TextIter cursor_iter, Gee.ArrayList<LspCodeActionResult> results) {
        // Если предыдущее окно открыто — уничтожаем
        if (this.code_actions_popup != null) {
            this.code_actions_popup.destroy ();
            this.code_actions_popup = null;
        }

        var root_window = this.get_root () as Gtk.Window;
        if (root_window == null)
            return;
        this.code_actions_popup = new Iide.CodeActionsPopup (root_window, this, results);
        this.code_actions_popup.present ();
    }

    public void show_code_actions_menu () {
        // Если меню уже открыто — закрываем его
        if (this.code_actions_popup != null) {
            this.code_actions_popup.destroy ();
            this.code_actions_popup = null;
        }

        var buffer = this.get_buffer ();
        Gtk.TextIter cursor_iter;
        buffer.get_iter_at_mark (out cursor_iter, buffer.get_insert ());
        int current_line = cursor_iter.get_line ();

        // 1. Собираем сырые диагностики текущей строки [INDEX]
        var raw_diagnostics = this.collect_raw_diagnostics_for_line (current_line);
        if (raw_diagnostics == null) {
            logger.info ("LCA", "No diagnostics on current line.");
            return;
        }

        lsp_document_client.request_code_actions.begin (this.uri, current_line, 0, current_line, 99, raw_diagnostics, (obj, res) => {
            var results = lsp_document_client.request_code_actions.end(res);
            logger.info ("LCA", "Code actions received: %d result(s).".printf (results.size));
            foreach (var r in results) {
                foreach (var a in r.actions) {
                    logger.info ("LCA", "  action '%s' kind='%s' from '%s' (%d edits for this uri)".printf (
                        a.title, a.kind, r.server_name,
                        a.changes.has_key (this.uri) ? a.changes.get (this.uri).size : -1
                    ));
                }
            }
            if (results.size == 0) {
                logger.info ("LCA", "LSP returned 0 available code actions.");
                return;
            }

            // Переводим выполнение обратно в главный цикл UI для рендеринга поповера [INDEX]
            Idle.add (() => {
                this.render_code_actions_popover (cursor_iter, results);
                return Source.REMOVE;
            });
        });
    }

    /**
     * ПЕРЕИМЕНОВАНИЕ СИМВОЛА ПОД КУРСОРОМ (Shift+F6)
     * Показывает диалог ввода нового имени, затем запрашивает textDocument/rename у LSP.
     */
    public void show_rename_dialog () {
        var buffer = this.get_buffer ();
        Gtk.TextIter cursor_iter;
        buffer.get_iter_at_mark (out cursor_iter, buffer.get_insert ());

        WordRange? word_range = get_word_range_under_cursor (cursor_iter);
        if (word_range == null) {
            logger.info ("LRN", "No word under cursor to rename.");
            return;
        }

        // Извлекаем текущее слово из буфера
        Gtk.TextIter start_iter, end_iter;
        buffer.get_iter_at_line_index (out start_iter, word_range.line, word_range.start_column);
        buffer.get_iter_at_line_index (out end_iter, word_range.line, word_range.end_column);
        string current_word = buffer.get_text (start_iter, end_iter, false).strip ();
        if (current_word == "") {
            logger.info ("LRN", "No word under cursor to rename.");
            return;
        }

        var root_window = this.get_root () as Gtk.Window;
        if (root_window == null)
            return;

        var rename_dialog = new Adw.AlertDialog (
            _("Rename Symbol"),
            _("Enter a new name for \"%s\"").printf (current_word)
        );
        rename_dialog.add_response ("cancel", _("Cancel"));
        rename_dialog.add_response ("rename", _("Rename"));
        rename_dialog.set_response_appearance ("rename", Adw.ResponseAppearance.SUGGESTED);
        rename_dialog.set_default_response ("rename");
        rename_dialog.set_close_response ("cancel");

        var entry = new Gtk.Entry () {
            text = current_word,
            placeholder_text = _("New name"),
            halign = Gtk.Align.FILL,
            margin_top = 12
        };
        entry.width_chars = 40;
        // Выделяем весь текст, чтобы ввод сразу заменил старое имя
        entry.select_region (0, current_word.length);

        rename_dialog.set_extra_child (entry);

        rename_dialog.response.connect ((response) => {
            if (response != "rename")
                return;
            this.try_apply_rename (entry, word_range, current_word);
        });

        // Enter в поле ввода подтверждает переименование и закрывает диалог
        entry.activate.connect (() => {
            if (this.try_apply_rename (entry, word_range, current_word))
                rename_dialog.close ();
        });

        rename_dialog.present (root_window);
        entry.grab_focus ();
    }

    private bool try_apply_rename (Gtk.Entry entry, WordRange word_range, string current_word) {
        string new_name = entry.text.strip ();
        if (new_name == "" || new_name == current_word)
            return false;

        this.perform_rename.begin (word_range, new_name);
        return true;
    }

    private async void perform_rename (WordRange word_range, string new_name) {
        logger.info ("LRN", "Requesting rename of symbol at %d:%d to '%s'...".printf (
            word_range.line, word_range.start_column, new_name
        ));

        var edits_map = yield this.lsp_document_client.request_rename_async (
            this.uri, word_range.line, word_range.start_column, new_name
        );

        if (edits_map == null || edits_map.is_empty) {
            logger.info ("LRN", "Rename returned no edits.");
            return;
        }

        this.apply_rename_edits (edits_map);
    }

    /**
     * Применение результата переименования (WorkspaceEdit).
     * Если все правки относятся к одному файлу (активному) — применяем автоматически.
     * Если правки затрагивают несколько файлов — показываем диалог подтверждения.
     */
    public void apply_rename_edits (Gee.HashMap<string, Gee.ArrayList<LspTextEdit>> edits_map) {
        if (edits_map.size == 1) {
            foreach (var entry in edits_map.entries) {
                this.session.document_manager.apply_edits_to_file (entry.key, entry.value);
            }
            return;
        }

        var root_window = this.get_root () as Gtk.Window;
        if (root_window == null)
            return;

        if (this.rename_preview_dialog != null) {
            this.rename_preview_dialog.destroy ();
            this.rename_preview_dialog = null;
        }

        this.rename_preview_dialog = new RenamePreviewDialog (root_window, this, edits_map);
        this.rename_preview_dialog.confirmed.connect ((selected_edits) => {
            foreach (var entry in selected_edits.entries) {
                this.session.document_manager.apply_edits_to_file (entry.key, entry.value);
            }
        });
        this.rename_preview_dialog.present ();
    }
}