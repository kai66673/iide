/*
*/

public class Iide.BreadcrumbSymbolOutlineNavigator : Gtk.Box {
    private SourceView source_view;
    public Gtk.SearchEntry search_entry;
    private Gtk.ListBox ts_list_box;
    private Gtk.ListBox lsp_list_box;
    private Gtk.Spinner spinner;
    private Gtk.Stack stack;
    private Gtk.ToggleButton back_button;

    public signal void close_requested ();

    private class BreadcrumbObject : Object {
        public SourceNodeItem item;
        public BreadcrumbObject (SourceNodeItem item) {
            Object ();
            this.item = item;
        }
    }

    public BreadcrumbSymbolOutlineNavigator (SourceView source_view) {
        Object (orientation: Gtk.Orientation.VERTICAL, spacing: 6);
        this.source_view = source_view;

        var header = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4);

        back_button = new Gtk.ToggleButton ();
        back_button.icon_name = "go-previous-symbolic";
        back_button.active = false;
        back_button.add_css_class ("flat");
        back_button.can_focus = false;
        
        this.set_size_request (300, -1);

        search_entry = new Gtk.SearchEntry ();
        search_entry.hexpand = true;

        header.append (back_button);
        header.append (search_entry);
        this.append (header);

        ts_list_box = new Gtk.ListBox ();
        ts_list_box.add_css_class ("navigation-sidebar");

        lsp_list_box = new Gtk.ListBox ();
        lsp_list_box.add_css_class ("navigation-sidebar");

        spinner = new Gtk.Spinner ();
        spinner.set_size_request (32, 32);

        var loading_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 12);
        loading_box.valign = Gtk.Align.CENTER;
        loading_box.halign = Gtk.Align.CENTER;

        var loading_label = new Gtk.Label ("Loading Document Synbols...");
        loading_label.add_css_class ("dim-label");

        loading_box.append (spinner);
        loading_box.append (loading_label);

        stack = new Gtk.Stack ();

        // Рекурсивно заполняем список с учетом отступов
        add_ts_symbols_recursively (source_view.ts_highlighter.get_full_outline (), 0);

        // Фильтрация
        ts_list_box.set_filter_func ((row) => {
            var text = search_entry.get_text ().down ();
            if (text == "")return true;

            var obj = row.get_data<BreadcrumbObject> ("item");
            var name = obj.item.name.down ();
            return name.contains (text);
        });
        search_entry.search_changed.connect (() => {
            ts_list_box.invalidate_filter ();
            refresh_state ();
        });

        ts_list_box.row_activated.connect (on_ts_row_activated);
        search_entry.activate.connect (() => {
            on_ts_row_activated (ts_list_box.get_selected_row ());
        });

        var ts_scroll = new Gtk.ScrolledWindow ();
        ts_scroll.propagate_natural_height = true;
        ts_scroll.set_max_content_height (400);
        ts_scroll.set_child (ts_list_box);
        stack.add_named (ts_scroll, "ts");

        stack.add_named (loading_box, "lsp_loading");

        var lsp_scroll = new Gtk.ScrolledWindow ();
        lsp_scroll.propagate_natural_height = true;
        lsp_scroll.set_max_content_height (400);
        lsp_scroll.set_child (lsp_list_box);
        stack.add_named (lsp_scroll, "lsp");
        
        stack.visible_child_name = "ts";

        this.append (stack);

        back_button.toggled.connect(toggle_mode);

        var key_controller = new Gtk.EventControllerKey ();
        key_controller.key_pressed.connect (on_key_pressed);
        search_entry.add_controller (key_controller);
        ts_list_box.set_selection_mode (Gtk.SelectionMode.SINGLE);
        lsp_list_box.set_selection_mode (Gtk.SelectionMode.SINGLE);

        this.refresh_state ();
    }

    private void toggle_mode() {
        if (!back_button.active) {
            spinner.stop ();
            stack.visible_child_name = "ts";
            return;
        }

        spinner.start ();
        stack.visible_child_name = "lsp_loading";
        
        document_symbols.begin ();
    }

    private async void document_symbols() {
        var symbols = yield IdeLspService.get_instance ().document_symbols (source_view.uri);
        spinner.stop ();
        stack.visible_child_name = "lsp";
    }

    private void select_ts_first_visible_row () {
        var row = ts_list_box.get_first_child ();
        while (row != null) {
            var list_row = row as Gtk.ListBoxRow;
            if (list_row.get_child_visible ()) {
                ts_list_box.select_row (list_row);
                break;
            }
            row = row.get_next_sibling ();
        }
    }

    private void refresh_state () {
        this.search_entry.grab_focus ();
        select_ts_first_visible_row ();
    }

    private bool on_key_pressed (Gtk.EventControllerKey controller, uint keyval, uint keycode, Gdk.ModifierType modifiers) {
        if (keyval == Gdk.Key.Escape) {
            close_requested ();
            return true;
        } else if (keyval == Gdk.Key.Up || keyval == Gdk.Key.KP_Up) {
            move_ts_selection_up ();
            return true;
        } else if (keyval == Gdk.Key.Down || keyval == Gdk.Key.KP_Down) {
            move_ts_selection_down ();
            return true;
        }
        return false;
    }

    private void move_ts_selection_down () {
        var selected_row = ts_list_box.get_selected_row ();
        if (selected_row == null) {
            select_ts_first_visible_row ();
            return;
        }

        var next_row_widget = selected_row.get_next_sibling ();
        while (next_row_widget != null) {
            var list_row = next_row_widget as Gtk.ListBoxRow;
            if (list_row.get_child_visible ()) {
                ts_list_box.select_row (list_row);
                return;
            }
            next_row_widget = next_row_widget.get_next_sibling ();
        }

        if (!selected_row.get_child_visible ())
            select_ts_first_visible_row ();
    }

    private void move_ts_selection_up () {
        var selected_row = ts_list_box.get_selected_row ();
        if (selected_row == null) {
            select_ts_first_visible_row ();
            return;
        }

        var prev_row_widget = selected_row.get_prev_sibling ();
        while (prev_row_widget != null) {
            var list_row = prev_row_widget as Gtk.ListBoxRow;
            if (list_row.get_child_visible ()) {
                ts_list_box.select_row (list_row);
                return;
            }
            prev_row_widget = prev_row_widget.get_prev_sibling ();
        }

        if (!selected_row.get_child_visible ())
            select_ts_first_visible_row ();
    }

    private void add_ts_symbols_recursively (Gee.List<SourceNodeItem?> symbols, int depth) {
        foreach (var sym in symbols) {
            var row = create_ts_symbol_row (sym, depth);
            ts_list_box.append (row);

            if (sym.children != null && sym.children.size > 0) {
                add_ts_symbols_recursively (sym.children, depth + 1);
            }
        }
    }

    private Gtk.ListBoxRow create_ts_symbol_row (SourceNodeItem item, int depth) {
        var row = new Gtk.ListBoxRow ();
        var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
        box.margin_start = 8 + (depth * 16); // Создаем визуальную иерархию
        box.margin_end = 8;
        box.margin_top = box.margin_bottom = 2;

        var icon = ImageFactory.create_for_ts (item.type);
        var label = new Gtk.Label (item.name);

        box.append (icon);
        box.append (label);
        row.set_child (box);

        // Сохраняем данные для поиска и активации
        row.set_data ("item", new BreadcrumbObject (item));
        return row;
    }

    private void on_ts_row_activated (Gtk.ListBoxRow row) {
        var obj = row.get_data<BreadcrumbObject> ("item");
        this.source_view.goto ((int) obj.item.start_point.row,
                               (int) obj.item.start_point.column);
        this.close_requested ();
    }
}