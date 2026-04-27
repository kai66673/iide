public class Iide.BreadcrumbTreeSitterNavigator : Gtk.Box {
    private SourceView source_view;
    private Gee.List<TreeSitterNodeItem?> siblings;
    public Gtk.SearchEntry search_entry;
    private Gtk.ListBox list_box;

    private class BreadcrumbObject : Object {
        public TreeSitterNodeItem item;
        public BreadcrumbObject (TreeSitterNodeItem item) {
            Object ();
            this.item = item;
        }
    }

    public BreadcrumbTreeSitterNavigator (SourceView source_view, Gee.List<TreeSitterNodeItem?> siblings) {
        Object (orientation: Gtk.Orientation.VERTICAL, spacing: 6);
        this.source_view = source_view;
        this.siblings = siblings;
        this.set_size_request (280, -1);
        this.margin_top = 6;
        this.margin_bottom = 6;
        this.margin_start = 6;
        this.margin_end = 6;

        // --- Поиск ---
        search_entry = new Gtk.SearchEntry ();
        search_entry.hexpand = true;
        this.append (search_entry);

        // --- Список элементов ---
        list_box = new Gtk.ListBox ();
        list_box.add_css_class ("navigation-sidebar");

        foreach (var item in siblings) {
            list_box.append (create_row (item));
        }

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

    private Gtk.ListBoxRow create_row (TreeSitterNodeItem item) {
        var row = new Gtk.ListBoxRow ();
        var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
        box.margin_bottom = 4;
        box.margin_top = 4;
        box.margin_start = 4;
        box.margin_end = 4;

        var icon = Iide.SymbolIconFactory.create_for_ts (item.type);

        var label = new Gtk.Label (item.name);
        label.ellipsize = Pango.EllipsizeMode.END;

        box.append (icon);
        box.append (label);
        row.set_child (box);

        // Сохраняем данные для поиска и активации
        row.set_data ("item", new BreadcrumbObject (item));

        return row;
    }

    private void on_row_activated (Gtk.ListBoxRow row) {
        var obj = row.get_data<BreadcrumbObject> ("item");
        source_view.goto ((int) obj.item.start_point.row,
                          (int) obj.item.start_point.column);
    }
}