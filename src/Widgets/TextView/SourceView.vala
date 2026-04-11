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
    public BaseTreeSitterHighlighter? ts_highlighter;
    public GutterMarkRenderer mark_renderer;
    public string icon_name = "text-x-generic";
    private Gtk.TextIter? pending_scroll_iter = null;

    private WordRange? last_hover_range = null;
    private LspTooltipWidget tooltip_widget;
    private string tooltip_separator = "────────────────────────────────────────";

    public SourceView (Window window, string uri, GtkSource.Buffer buffer) {
        Object (buffer : buffer);
        this.window = window;
        this.uri = uri;
        this.ts_manager = new TreeSitterManager ();
        this.ts_highlighter = null;

        this.tooltip_widget = new LspTooltipWidget ();

        // LSP-complete
        var completion = get_completion ();
        completion.show_icons = false; // Упрощаем попап, чтобы не ломать размеры
        completion.remember_info_visibility = false;
        var provider = new LspCompletionProvider (this);
        completion.add_provider (provider);

        // Build extra menu for context menu
        var zoom_section = new GLib.Menu ();
        zoom_section.append (_("Zoom In"), "app.zoom_in");
        zoom_section.append (_("Zoom Out"), "app.zoom_out");
        zoom_section.append (_("Reset Zoom"), "app.zoom_reset");

        var view_section = new GLib.Menu ();
        view_section.append (_("Minimap"), "app.toggle_minimap");

        var extra_menu = new GLib.Menu ();
        extra_menu.append_section (null, zoom_section);
        extra_menu.append_section (null, view_section);
        this.extra_menu = extra_menu;

        var settings = Iide.SettingsService.get_instance ();

        show_line_numbers = settings.show_line_numbers;
        highlight_current_line = settings.highlight_current_line;
        auto_indent = settings.auto_indent;
        indent_on_tab = true;

        // Marks gutter
        set_show_line_marks (false);
        var left_gutter = get_gutter (Gtk.TextWindowType.LEFT);
        left_gutter.visible = true;

        mark_renderer = new GutterMarkRenderer ();
        mark_renderer.set_icons_size (FontSizeHelper.get_size_for_zoom_level (settings.editor_font_size));
        left_gutter.insert (mark_renderer, 0);

        LspDiagnosticsMark.set_mark_attributes (this);

        // Connect to settings changes to apply to all open documents
        settings.editor_setting_changed.connect ((key) => {
            switch (key) {
                case "show-line-numbers" :
                    show_line_numbers = settings.show_line_numbers;
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

        // Tree-sitter
        detect_language ();
        ts_highlighter = ts_manager.get_ts_highlighter (this);
        if (ts_highlighter != null) {
            ((GtkSource.Buffer) (buffer)).highlight_syntax = false;
        }

        // LSP-tooltips
        has_tooltip = true;
        query_tooltip.connect (on_query_tooltip);

        // Control-click controller (goto definition)
        var click_gest = new Gtk.GestureClick ();
        click_gest.set_button (1);
        click_gest.pressed.connect (on_click_pressed);
        add_controller (click_gest);

        buffer.set_modified (false);
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

        icon_name = IconProvider.get_mime_type_icon_name (mime_type);
        language = manager.guess_language (file.get_path (), mime_type);

        // Fake file type detection
        // "Not all files are equal"
        if (file.get_basename () == "CMakeLists.txt") {
            language = manager.get_language ("cmake");
            icon_name = "text-x-cmake"; // Specific icon for CMake
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

        tooltip_widget.update_text (markdown, false);
    }

    private void on_click_pressed (Gtk.GestureClick gesture, int n_press, double x, double y) {
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
        window.get_document_manager ().open_document_with_selection (File.new_for_uri (loc.uri), loc.start_line, loc.start_column, loc.end_column, null);
    }

    public void select_and_scroll (int line, int start_col, int end_col, bool is_new) {
        if (line >= buffer.get_line_count ()) {
            return;
        }

        Gtk.TextIter start_iter;
        buffer.get_iter_at_line_offset (out start_iter, line, start_col);

        Gtk.TextIter end_iter;
        buffer.get_iter_at_line_offset (out end_iter, line, end_col);

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
}
