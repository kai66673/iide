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
    public Window window;
    public string uri { get; private set; }
    private Iide.TreeSitterManager ts_manager;
    public Iide.LineNumbersGutter line_numbers_gutter;
    public GutterMarkRenderer mark_renderer;
    public TreeSitterFoldingGutter folding_gutter;
    private Gtk.TextIter? pending_scroll_iter = null;

    private WordRange? last_hover_range = null;
    private LspTooltipWidget tooltip_widget;
    private string tooltip_separator = "────────────────────────────────────────";

    private LspDocumentClient lsp_doclument_client;
    public SourceDocument document;

    private int last_line = -1;
    private NavigationHistoryService history;

    public signal void breadcrumbs_changed (Gee.List<SourceNodeItem?> crumbs);

    public SourceView (Window window, string uri, GtkSource.Buffer buffer) {
        Object (buffer : buffer);
        this.window = window;
        this.uri = uri;
        this.ts_manager = new TreeSitterManager ();
        this.history = NavigationHistoryService.get_instance ();

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

        show_line_numbers = false;
        this.line_numbers_gutter = new Iide.LineNumbersGutter ();
        left_gutter.insert (this.line_numbers_gutter, 0); // Вес 0 — самая левая позиция
        line_numbers_gutter.visible = settings.show_line_numbers;

        mark_renderer = new GutterMarkRenderer ();
        mark_renderer.set_icons_size (FontSizeHelper.get_size_for_zoom_level (settings.editor_font_size));
        left_gutter.insert (mark_renderer, 10);

        this.folding_gutter = new TreeSitterFoldingGutter ();
        this.folding_gutter.set_icons_size (FontSizeHelper.get_size_for_zoom_level (settings.editor_font_size));
        left_gutter.insert (this.folding_gutter, 20);

        LspDiagnosticsMark.set_mark_attributes (this);

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
        } else {
            this.document = new SourceDocument (this);
            this.folding_gutter.visible = false;
            this.mark_renderer.visible = false;
        }

        this.lsp_doclument_client = new LspDocumentClient (this);
        this.document.document_changed.connect(this.lsp_doclument_client.add_change);
        this.document.breadcrumbs_changed.connect ((crumbs) => {
            this.breadcrumbs_changed(crumbs);
        });
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
        yield this.lsp_doclument_client.sync_changes_async ();
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

    // Этот метод вызывается при открытии файла
    public void bind_lsp_client (LspClient? client) {
        this.lsp_doclument_client.bind_lsp_client (client);
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

    public WordRange ? get_word_range_under_cursor (Gtk.TextIter cursor_iter) {
        // 2. Нюанс: Если курсор на пробеле или переносе строки, слова под ним нет
        unichar c = cursor_iter.get_char ();
        if (c.isspace () || c == '\0') {
            return null;
        }

        // 3. Создаем копию для поиска конца слова
        Gtk.TextIter end_iter = cursor_iter;

        // 4. Ищем начало слова
        // Если курсор уже в начале слова, backward_word_start вернет false или уйдет на слово назад.
        // Поэтому проверяем, не стоим ли мы уже на начале.
        if (!cursor_iter.starts_word ()) {
            cursor_iter.backward_word_start ();
        }

        // 5. Ищем конец слова
        if (!end_iter.ends_word ()) {
            end_iter.forward_word_end ();
        }

        return new WordRange (cursor_iter.get_line (), cursor_iter.get_line_offset (), end_iter.get_line_offset ());
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
            sb.append_printf ("%s <span font_weight='bold' foreground='%s'>%s</span>\n",
                              icon, header_color, lsp_mark.category.up ());
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

        this.lsp_doclument_client.flush_changes ();
        fetch_lsp_hover_async.begin (word_range.line, word_range.start_column + 1);

        return true;
    }

    private bool on_query_tooltip (int x, int y, bool keyboard_mode, Gtk.Tooltip tooltip) {
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

        return on_lsp_hover_tooltip (iter, tooltip);
    }

    private async void fetch_lsp_hover_async (int line, int col) {
        var lsp_service = IdeLspService.get_instance ();
        string? markdown = yield lsp_service.request_hover (uri, line, col);

        tooltip_widget.update_text (escape_pango (markdown), false);
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
                this.lsp_doclument_client.flush_changes ();
                handle_ctrl_click_async.begin (iter.get_line (), iter.get_line_offset ());
            }
        }
    }

    private async void handle_ctrl_click_async (int line, int col) {
        var lsp_service = IdeLspService.get_instance ();
        var locations = yield lsp_service.goto_definition (uri, line, col);

        if (locations == null || locations.size == 0) {
            LoggerService.get_instance ().warning ("LSP", "No locations found for goto definition");
            return;
        }

        var loc = locations.get (0);
        if (this.uri == loc.uri) {
            this.select_and_scroll (loc.start_line, loc.start_column, loc.end_column, false);
        } else {
            window.get_document_manager ().open_document_with_selection
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
}