public class Iide.BreadcrumbSymbolOutlineNavigator : Gtk.Box {
    private SourceView source_view;
    public Gtk.SearchEntry search_entry;
    private Gtk.ListBox list_box;

    public signal void close_requested ();

    private class BreadcrumbObject : Object {
        public TreeSitterNodeItem item;
        public BreadcrumbObject (TreeSitterNodeItem item) {
            Object ();
            this.item = item;
        }
    }

    public BreadcrumbSymbolOutlineNavigator (SourceView source_view) {
        Object (orientation: Gtk.Orientation.VERTICAL, spacing: 6);
        this.source_view = source_view;
        this.set_size_request (300, -1);

        search_entry = new Gtk.SearchEntry ();
        this.append (search_entry);

        list_box = new Gtk.ListBox ();
        list_box.add_css_class ("navigation-sidebar");

        // Рекурсивно заполняем список с учетом отступов
        add_symbols_recursively (source_view.ts_highlighter.get_full_outline (), 0);

        // Фильтрация
        list_box.set_filter_func ((row) => {
            var text = search_entry.get_text ().down ();
            if (text == "")return true;

            var obj = row.get_data<BreadcrumbObject> ("item");
            var name = obj.item.name.down ();
            return name.contains (text);
        });
        search_entry.search_changed.connect (() => {
            list_box.invalidate_filter ();
            refresh_state ();
        });

        list_box.row_activated.connect (on_row_activated);
        search_entry.activate.connect (() => {
            on_row_activated (list_box.get_selected_row ());
        });

        var scroll = new Gtk.ScrolledWindow ();
        scroll.propagate_natural_height = true;
        scroll.set_max_content_height (400);
        scroll.set_child (list_box);
        this.append (scroll);

        var key_controller = new Gtk.EventControllerKey ();
        key_controller.key_pressed.connect (on_key_pressed);
        search_entry.add_controller (key_controller);
        list_box.set_selection_mode (Gtk.SelectionMode.SINGLE);

        this.refresh_state ();
    }

    private void select_first_visible_row () {
        var row = list_box.get_first_child ();
        while (row != null) {
            var list_row = row as Gtk.ListBoxRow;
            if (list_row.get_child_visible ()) {
                list_box.select_row (list_row);
                break;
            }
            row = row.get_next_sibling ();
        }
    }

    private void refresh_state () {
        this.search_entry.grab_focus ();
        select_first_visible_row ();
    }

    private bool on_key_pressed (Gtk.EventControllerKey controller, uint keyval, uint keycode, Gdk.ModifierType modifiers) {
        if (keyval == Gdk.Key.Escape) {
            close_requested ();
            return true;
        } else if (keyval == Gdk.Key.Up || keyval == Gdk.Key.KP_Up) {
            move_selection_up ();
            return true;
        } else if (keyval == Gdk.Key.Down || keyval == Gdk.Key.KP_Down) {
            move_selection_down ();
            return true;
        }
        return false;
    }

    private void move_selection_down () {
        var selected_row = list_box.get_selected_row ();
        if (selected_row == null) {
            select_first_visible_row ();
            return;
        }

        var next_row_widget = selected_row.get_next_sibling ();
        while (next_row_widget != null) {
            var list_row = next_row_widget as Gtk.ListBoxRow;
            if (list_row.get_child_visible ()) {
                list_box.select_row (list_row);
                return;
            }
            next_row_widget = next_row_widget.get_next_sibling ();
        }

        if (!selected_row.get_child_visible ())
            select_first_visible_row ();
    }

    private void move_selection_up () {
        var selected_row = list_box.get_selected_row ();
        if (selected_row == null) {
            select_first_visible_row ();
            return;
        }

        var prev_row_widget = selected_row.get_prev_sibling ();
        while (prev_row_widget != null) {
            var list_row = prev_row_widget as Gtk.ListBoxRow;
            if (list_row.get_child_visible ()) {
                list_box.select_row (list_row);
                return;
            }
            prev_row_widget = prev_row_widget.get_prev_sibling ();
        }

        if (!selected_row.get_child_visible ())
            select_first_visible_row ();
    }

    private void add_symbols_recursively (Gee.List<TreeSitterNodeItem?> symbols, int depth) {
        foreach (var sym in symbols) {
            var row = create_symbol_row (sym, depth);
            list_box.append (row);

            if (sym.children != null && sym.children.size > 0) {
                add_symbols_recursively (sym.children, depth + 1);
            }
        }
    }

    private Gtk.ListBoxRow create_symbol_row (TreeSitterNodeItem item, int depth) {
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
        this.source_view.goto ((int) obj.item.start_point.row,
                               (int) obj.item.start_point.column);
        this.close_requested ();
    }
}