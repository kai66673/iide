public class Iide.BreadcrumbSymbolOutlineNavigator : Gtk.Box {
    public Gtk.SearchEntry search_entry;
    private Gtk.ListBox list_box;

    public signal void breadcrumb_clicked (uint line, uint column);

    private class BreadcrumbObject : Object {
        public BreadcrumbItem item;
        public BreadcrumbObject (BreadcrumbItem item) {
            Object ();
            this.item = item;
        }
    }

    public BreadcrumbSymbolOutlineNavigator (Gee.List<BreadcrumbItem?> full_outline) {
        Object (orientation: Gtk.Orientation.VERTICAL, spacing: 6);
        this.set_size_request (300, 400); // Оутлайн обычно длиннее

        search_entry = new Gtk.SearchEntry ();
        this.append (search_entry);

        list_box = new Gtk.ListBox ();
        list_box.add_css_class ("navigation-sidebar");

        // Рекурсивно заполняем список с учетом отступов
        add_symbols_recursively (full_outline, 0);

        // Фильтрация
        list_box.set_filter_func ((row) => {
            var text = search_entry.get_text ().down ();
            if (text == "")return true;

            var obj = row.get_data<BreadcrumbObject> ("item");
            var name = obj.item.name.down ();
            return name.contains (text);
        });
        search_entry.search_changed.connect (() => { list_box.invalidate_filter (); });

        list_box.row_activated.connect (on_row_activated);

        var scroll = new Gtk.ScrolledWindow ();
        scroll.propagate_natural_height = true;
        scroll.set_max_content_height (400);
        scroll.set_child (list_box);
        this.append (scroll);

        this.search_entry.grab_focus ();
    }

    private void add_symbols_recursively (Gee.List<BreadcrumbItem?> symbols, int depth) {
        foreach (var sym in symbols) {
            var row = create_symbol_row (sym, depth);
            list_box.append (row);

            if (sym.children != null && sym.children.size > 0) {
                add_symbols_recursively (sym.children, depth + 1);
            }
        }
    }

    private Gtk.ListBoxRow create_symbol_row (BreadcrumbItem item, int depth) {
        var row = new Gtk.ListBoxRow ();
        var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
        box.margin_start = 8 + (depth * 16); // Создаем визуальную иерархию
        box.margin_end = 8;
        box.margin_top = box.margin_bottom = 2;

        var icon = Iide.SymbolIconFactory.create_for_ts (item.type);
        var label = new Gtk.Label (item.name);

        box.append (icon);
        box.append (label);
        row.set_child (box);

        // Сохраняем данные для поиска и активации
        row.set_data ("item", new BreadcrumbObject (item));
        return row;
    }

    private void on_row_activated (Gtk.ListBoxRow row) {
        var obj = row.get_data<BreadcrumbObject> ("item");
        this.breadcrumb_clicked (obj.item.start_point.row, obj.item.start_point.column);
    }
}