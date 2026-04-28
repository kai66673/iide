public class Iide.BreadcrumbTreeSitterNavigator : Gtk.Box {
    private SourceView source_view;
    private Gee.List<TreeSitterNodeItem?> siblings;
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