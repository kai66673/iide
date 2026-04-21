public class Iide.SearchSymbolRow : Gtk.ListBoxRow {
    public LspSymbol symbol { get; private set; }

    public SearchSymbolRow (LspSymbol symbol) {
        this.symbol = symbol;

        var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
        box.margin_start = 8;
        box.margin_end = 8;
        box.margin_bottom = 8;
        box.margin_top = 8;

        // Иконка типа символа (Class, Function и т.д.)
        var icon = new Gtk.Image.from_icon_name (symbol.kind.to_icon_name ());

        // Название символа
        var label_name = new Gtk.Label (symbol.name);
        label_name.add_css_class ("bold");

        // Путь к файлу (обрезаем длинные пути слева)
        string display_path = symbol.uri.replace ("file://", "");
        var label_path = new Gtk.Label (display_path);
        label_path.add_css_class ("dim-label");
        label_path.ellipsize = Pango.EllipsizeMode.START;
        label_path.hexpand = true;
        label_path.halign = Gtk.Align.END;
        label_path.max_width_chars = 30;

        box.append (icon);
        box.append (label_name);
        box.append (label_path);
        set_child (box);
    }
}

public class Iide.SearchSymbolPage : Gtk.Box, SearchPanelInterface {
    private Gtk.SearchEntry search_entry;
    private Gtk.ListBox results_list;
    private Gtk.Stack status_stack; // Заменили простую переменную на поле класса
    private Adw.StatusPage empty_state;

    private GLib.Cancellable? search_cancellable = null;
    private uint debounce_id = 0;

    public SearchSymbolPage () {
        Object (orientation : Gtk.Orientation.VERTICAL, spacing: 0);

        // Поле поиска
        var search_bar_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
        search_bar_box.add_css_class ("view");

        search_entry = new Gtk.SearchEntry ();
        search_entry.margin_start = 12;
        search_entry.margin_end = 12;
        search_entry.margin_bottom = 12;
        search_entry.margin_top = 12;
        search_entry.hexpand = true;
        search_entry.placeholder_text = "Поиск функций, классов, переменных (мин. 3 символа)...";
        search_entry.search_changed.connect (on_search_changed);

        search_bar_box.append (search_entry);
        append (search_bar_box);

        status_stack = new Gtk.Stack ();
        status_stack.transition_type = Gtk.StackTransitionType.CROSSFADE;

        // Список результатов
        results_list = new Gtk.ListBox ();
        results_list.selection_mode = Gtk.SelectionMode.SINGLE;
        results_list.add_css_class ("navigation-sidebar");
        results_list.row_activated.connect (on_row_activated);

        var scrolled_window = new Gtk.ScrolledWindow ();
        scrolled_window.set_child (results_list);
        scrolled_window.vexpand = true;

        // Состояние "Ничего не найдено" / Инструкция
        empty_state = new Adw.StatusPage ();
        empty_state.title = "Символы не найдены";
        empty_state.icon_name = "edit-find-symbolic";
        empty_state.description = "Введите название для поиска в проекте";

        // Состояние "Загрузка"
        var loading_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 12);
        loading_box.valign = Gtk.Align.CENTER;
        var spinner = new Gtk.Spinner ();
        spinner.start ();
        spinner.set_size_request (32, 32);
        loading_box.append (spinner);

        status_stack.add_named (scrolled_window, "results");
        status_stack.add_named (empty_state, "empty");
        status_stack.add_named (loading_box, "loading");

        append (status_stack);
        status_stack.visible_child_name = "empty";

        var key_controller = new Gtk.EventControllerKey ();
        key_controller.key_pressed.connect (on_key_pressed);
        search_entry.add_controller (key_controller);
    }

    private void select_next_item () {
        // 1. Получаем текущую выделенную строку
        var selected_row = results_list.get_selected_row ();

        int next_index = 0;

        if (selected_row != null) {
            // 2. Если что-то выделено, берем индекс следующего элемента
            next_index = selected_row.get_index () + 1;
        }

        // 3. Получаем строку по новому индексу
        var next_row = results_list.get_row_at_index (next_index);

        // 4. Если строка существует (мы не вышли за пределы списка), выделяем её
        if (next_row != null) {
            results_list.select_row (next_row);
        }
    }

    private void select_prev_item () {
        // 1. Получаем текущую выделенную строку
        var selected_row = results_list.get_selected_row ();

        int prev_index = 0;

        if (selected_row != null) {
            // 2. Если что-то выделено, берем индекс следующего элемента
            prev_index = selected_row.get_index () - 1;
        }

        // 3. Получаем строку по новому индексу
        var prev_row = results_list.get_row_at_index (prev_index);

        // 4. Если строка существует (мы не вышли за пределы списка), выделяем её
        if (prev_row != null) {
            results_list.select_row (prev_row);
        }
    }

    private bool on_key_pressed (Gtk.EventControllerKey controller, uint keyval, uint keycode, Gdk.ModifierType modifiers) {
        if (keyval == Gdk.Key.Escape) {
            close_requested ();
            return true;
        } else if (keyval == Gdk.Key.Return || keyval == Gdk.Key.KP_Enter) {
            // open_selected ((modifiers & Gdk.ModifierType.SHIFT_MASK) != 0);
            return true;
        } else if (keyval == Gdk.Key.Up || keyval == Gdk.Key.KP_Up) {
            select_prev_item ();
            return true;
        } else if (keyval == Gdk.Key.Down || keyval == Gdk.Key.KP_Down) {
            select_next_item ();
            return true;
        }
        return false;
    }

    private void on_search_changed () {
        // 1. Сброс debounce таймера
        if (debounce_id > 0) {
            GLib.Source.remove (debounce_id);
            debounce_id = 0;
        }

        string query = search_entry.get_text ().strip ();
        if (query.length < 3) {
            clear_results ();
            status_stack.visible_child_name = "empty";
            return;
        }

        // 2. Установка задержки 300мс
        debounce_id = GLib.Timeout.add (300, () => {
            query_lsp_symbols.begin (query);
            debounce_id = 0;
            return false;
        });
    }

    private async void query_lsp_symbols (string query) {
        // Отменяем предыдущий запрос
        if (search_cancellable != null) {
            search_cancellable.cancel ();
        }
        search_cancellable = new GLib.Cancellable ();

        status_stack.visible_child_name = "loading";

        try {
            // Получаем клиент из вашего сервиса (проверьте имя синглтона)
            var client = IdeLspService.get_instance ().get_client ();
            if (client != null) {
                var symbols = yield client.workspace_symbols (query, search_cancellable);

                update_results (symbols);
            }
        } catch (GLib.IOError.CANCELLED e) {
            // Игнорируем
        } catch (GLib.Error e) {
            warning ("LSP Symbol Search Error: %s", e.message);
            status_stack.visible_child_name = "empty";
        }
    }

    private void update_results (Gee.List<LspSymbol>? symbols) {
        clear_results ();

        if (symbols == null || symbols.size == 0) {
            status_stack.visible_child_name = "empty";
            return;
        }

        foreach (var sym in symbols) {
            var row = new SearchSymbolRow (sym);
            results_list.append (row);
        }

        status_stack.visible_child_name = "results";
    }

    private void clear_results () {
        while (results_list.get_first_child () != null) {
            results_list.remove (results_list.get_first_child ());
        }
    }

    private void on_row_activated (Gtk.ListBoxRow row) {
        var symbol_row = row as SearchSymbolRow;
        if (symbol_row != null) {
            var sym = symbol_row.symbol;
            // Вызываем открытие файла в редакторе
            // ProjectManager.get_instance ().open_file (sym.uri, sym.start_line, sym.start_char);

            // Закрываем диалог (SearchCenterDialog)
            var root = this.get_root () as Gtk.Window;
            if (root != null)root.close ();
        }
    }

    public void focus_search_entry () {
        search_entry.grab_focus ();
    }

    public void handle_activated () {
        // Вызывается, если нажали Enter в пустом поле или на вкладке
        var selected = results_list.get_selected_row ();
        if (selected != null)on_row_activated (selected);
    }
}
