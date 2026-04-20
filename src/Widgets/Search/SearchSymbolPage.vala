public class Iide.SearchSymbolRow : Gtk.ListBoxRow {
    public string file_path;
    public int line;

    public SearchSymbolRow (string name, string detail, string icon_name) {
        var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
        box.margin_bottom = 8;
        box.margin_start = 8;
        box.margin_end = 8;
        box.margin_top = 8;

        var icon = new Gtk.Image.from_icon_name (icon_name);
        var label_name = new Gtk.Label (name);
        label_name.add_css_class ("bold");

        var label_detail = new Gtk.Label (detail);
        label_detail.add_css_class ("dim-label");
        label_detail.ellipsize = Pango.EllipsizeMode.END;

        box.append (icon);
        box.append (label_name);
        box.append (label_detail);
        set_child (box);
    }
}

public class Iide.SearchSymbolPage : Gtk.Box, SearchPanelInterface {
    private Gtk.SearchEntry search_entry;
    private Gtk.ListBox results_list;
    private Gtk.ScrolledWindow scrolled_window;
    private Adw.StatusPage empty_state;

    public void focus_search_entry () {
        search_entry.grab_focus ();
    }

    public SearchSymbolPage () {
        Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);

        // Поле поиска
        var search_bar_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
        search_bar_box.add_css_class ("view"); // Добавляем фон как у редактора

        search_entry = new Gtk.SearchEntry ();
        search_entry.margin_bottom = 12;
        search_entry.margin_start = 12;
        search_entry.margin_end = 12;
        search_entry.margin_top = 12;
        search_entry.hexpand = true;
        search_entry.placeholder_text = "Поиск функций, классов, переменных...";
        search_entry.search_changed.connect (on_search_changed);

        search_bar_box.append (search_entry);
        append (search_bar_box);

        // Стек для отображения результатов или пустой страницы
        var stack = new Gtk.Stack ();

        // Список результатов
        results_list = new Gtk.ListBox ();
        results_list.selection_mode = Gtk.SelectionMode.SINGLE;
        results_list.add_css_class ("navigation-sidebar"); // Стиль GNOME
        results_list.row_activated.connect (on_row_activated);

        scrolled_window = new Gtk.ScrolledWindow ();
        scrolled_window.set_child (results_list);
        scrolled_window.vexpand = true;

        // Состояние "Ничего не найдено"
        empty_state = new Adw.StatusPage ();
        empty_state.title = "Символы не найдены";
        empty_state.icon_name = "edit-find-symbolic";
        empty_state.description = "Начните вводить название, чтобы найти его в проекте";

        stack.add_named (scrolled_window, "results");
        stack.add_named (empty_state, "empty");
        append (stack);

        // По умолчанию показываем пустую страницу
        stack.visible_child_name = "empty";
    }

    public void handle_activated () {}

    private void on_search_changed () {
        string query = search_entry.get_text ();
        if (query.length < 2) {
            // Очищаем и выходим, если запрос слишком короткий
            clear_results ();
            return;
        }

        // Здесь будет вызов LSP
        query_lsp_symbols (query);
    }

    private void query_lsp_symbols (string query) {
        // TODO: Интеграция с IdeLspService
        // debug ("Поиск символа: %s", query);

        // Временная заглушка для теста UI
        update_results_placeholder (query);
    }

    private void update_results_placeholder (string query) {
        clear_results ();
        // Логика наполнения ListBox результатами будет здесь
        // (будем создавать SearchSymbolRow для каждого LSP SymbolInformation)
    }

    private void clear_results () {
        while (results_list.get_first_child () != null) {
            results_list.remove (results_list.get_first_child ());
        }
    }

    private void on_row_activated (Gtk.ListBoxRow row) {
        // Логика перехода к файлу и строке символа
    }
}
