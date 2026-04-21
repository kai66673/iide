public class Iide.SearchSymbolPage : Gtk.Box, SearchPanelInterface {
    private Gtk.SearchEntry search_entry;
    private Gtk.ListView list_view;
    private Gtk.SingleSelection selection;
    private Gtk.StringList string_list;
    private Gtk.Stack status_stack;
    private Gtk.Spinner spinner;

    private GLib.Cancellable? search_cancellable = null;
    private uint debounce_id = 0;

    private Iide.DocumentManager document_manager;
    private Gee.List<LspSymbol> symbols;
    private const int MAX_RESULTS = 50;

    public SearchSymbolPage (Iide.DocumentManager document_manager) {
        Object (orientation : Gtk.Orientation.VERTICAL, spacing: 0);
        this.document_manager = document_manager;
        this.symbols = new Gee.ArrayList<LspSymbol> ();

        setup_ui ();
    }

    private void setup_ui () {
        var search_bar_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
        search_bar_box.add_css_class ("view");

        search_entry = new Gtk.SearchEntry ();
        search_entry.margin_start = 12;
        search_entry.margin_end = 12;
        search_entry.margin_bottom = 12;
        search_entry.margin_top = 12;
        search_entry.hexpand = true;
        search_entry.placeholder_text = _("Search functions, classes, variables (min 3 chars)...");
        search_entry.search_changed.connect (on_search_changed);

        search_bar_box.append (search_entry);
        append (search_bar_box);

        status_stack = new Gtk.Stack ();
        status_stack.transition_type = Gtk.StackTransitionType.CROSSFADE;

        string_list = new Gtk.StringList (new string[0]);
        selection = new Gtk.SingleSelection (string_list);
        list_view = new Gtk.ListView (selection, null);
        list_view.hexpand = true;
        list_view.vexpand = true;
        list_view.show_separators = true;

        var factory = new Gtk.SignalListItemFactory ();
        factory.setup.connect ((item) => {
            var list_item = item as Gtk.ListItem;
            var item_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
            item_box.margin_start = 8;
            item_box.margin_end = 8;
            item_box.margin_top = 6;
            item_box.margin_bottom = 6;

            var icon = new Gtk.Image ();
            icon.set_size_request (20, 20);

            var text_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 2);
            text_box.hexpand = true;

            var name_label = new Gtk.Label (null);
            name_label.xalign = 0;
            name_label.add_css_class ("title-5");
            name_label.hexpand = true;

            var path_label = new Gtk.Label (null);
            path_label.add_css_class ("dim-label");
            path_label.add_css_class ("caption");
            path_label.xalign = 0;
            path_label.ellipsize = Pango.EllipsizeMode.START;
            path_label.hexpand = true;

            text_box.append (name_label);
            text_box.append (path_label);

            item_box.append (icon);
            item_box.append (text_box);
            list_item.set_child (item_box);
        });

        factory.bind.connect ((item) => {
            var list_item = item as Gtk.ListItem;
            var item_box = list_item.get_child () as Gtk.Box;
            var icon = item_box.get_first_child () as Gtk.Image;
            var text_box = icon.get_next_sibling () as Gtk.Box;
            var name_label = text_box.get_first_child () as Gtk.Label;
            var path_label = name_label.get_next_sibling () as Gtk.Label;

            var index = list_item.get_position ();
            if (index >= 0 && index < symbols.size) {
                var sym = symbols[(int) index];
                icon.set_from_icon_name (sym.kind.to_icon_name ());
                name_label.set_label (sym.name);
                path_label.set_label (sym.uri.replace ("file://", ""));
            }
        });

        list_view.factory = factory;

        var scrolled = new Gtk.ScrolledWindow ();
        scrolled.child = list_view;
        scrolled.hexpand = true;
        scrolled.vexpand = true;

        var loading_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 12);
        loading_box.valign = Gtk.Align.CENTER;
        loading_box.halign = Gtk.Align.CENTER;

        spinner = new Gtk.Spinner ();
        spinner.set_size_request (32, 32);

        var loading_label = new Gtk.Label (_("Searching symbols..."));
        loading_label.add_css_class ("dim-label");

        loading_box.append (spinner);
        loading_box.append (loading_label);

        status_stack.add_named (scrolled, "results");
        status_stack.add_named (loading_box, "loading");

        append (status_stack);
        status_stack.visible_child_name = "results";

        var key_controller = new Gtk.EventControllerKey ();
        key_controller.key_pressed.connect (on_key_pressed);
        search_entry.add_controller (key_controller);

        list_view.activate.connect (on_list_activated);
        search_entry.activate.connect (on_entry_activated);
    }

    private bool on_key_pressed (Gtk.EventControllerKey controller, uint keyval, uint keycode, Gdk.ModifierType modifiers) {
        if (keyval == Gdk.Key.Escape) {
            close_requested ();
            return true;
        } else if (keyval == Gdk.Key.Return || keyval == Gdk.Key.KP_Enter) {
            open_selected ((modifiers & Gdk.ModifierType.SHIFT_MASK) == 0);
            return true;
        } else if (keyval == Gdk.Key.Up || keyval == Gdk.Key.KP_Up) {
            if (string_list != null && selection.selected > 0) {
                selection.selected -= 1;
                list_view.scroll_to (selection.selected, Gtk.ListScrollFlags.NONE, null);
            }
            return true;
        } else if (keyval == Gdk.Key.Down || keyval == Gdk.Key.KP_Down) {
            if (string_list != null && selection.selected < (int) string_list.get_n_items () - 1) {
                selection.selected += 1;
                list_view.scroll_to (selection.selected, Gtk.ListScrollFlags.NONE, null);
            }
            return true;
        }
        return false;
    }

    private void on_search_changed () {
        if (debounce_id > 0) {
            GLib.Source.remove (debounce_id);
            debounce_id = 0;
        }

        string query = search_entry.get_text ().strip ();
        if (query.length < 3) {
            symbols.clear ();
            update_results ();
            status_stack.visible_child_name = "results";
            return;
        }

        debounce_id = GLib.Timeout.add (300, () => {
            query_lsp_symbols.begin (query);
            debounce_id = 0;
            return false;
        });
    }

    private async void query_lsp_symbols (string query) {
        if (search_cancellable != null) {
            search_cancellable.cancel ();
        }
        search_cancellable = new GLib.Cancellable ();

        status_stack.visible_child_name = "loading";
        spinner.start ();

        try {
            var client = IdeLspService.get_instance ().get_client ();
            if (client != null) {
                var results = yield client.workspace_symbols (query, search_cancellable);

                update_results_list (results);
            }
        } catch (GLib.IOError.CANCELLED e) {
        } catch (GLib.Error e) {
            warning ("LSP Symbol Search Error: %s", e.message);
            status_stack.visible_child_name = "results";
        }

        spinner.stop ();
    }

    private void update_results_list (Gee.List<LspSymbol>? results) {
        symbols.clear ();

        if (results == null || results.size == 0) {
            status_stack.visible_child_name = "results";
            update_results ();
            return;
        }

        var count = 0;
        foreach (var sym in results) {
            if (count >= MAX_RESULTS)break;
            symbols.add (sym);
            count++;
        }

        status_stack.visible_child_name = "results";
        update_results ();
    }

    private void update_results () {
        var strings = new string[symbols.size];
        for (int i = 0; i < symbols.size; i++) {
            var sym = symbols[i];
            strings[i] = "%s  →  %s".printf (sym.name, sym.uri.replace ("file://", ""));
        }

        string_list.splice (0, string_list.get_n_items (), strings);

        if (symbols.size > 0) {
            selection.selected = 0;
        }
    }

    private void on_list_activated () {
        open_selected ();
    }

    private void on_entry_activated () {
        open_selected ();
    }

    private void open_selected (bool close_search = true) {
        if (document_manager == null || symbols == null || symbols.size == 0) {
            if (close_search) {
                close_requested ();
            }
            return;
        }

        var index = (int) selection.selected;
        if (index < 0 || index >= symbols.size) {
            if (close_search) {
                close_requested ();
            }
            return;
        }

        var sym = symbols[index];
        var file = GLib.File.new_for_path (sym.uri.replace ("file://", ""));

        if (file.get_path () != null) {
            document_manager.open_document_with_selection (file, sym.start_line, sym.start_char, sym.start_char, null);
        }

        if (close_search) {
            close_requested ();
        }
    }

    public void focus_search_entry () {
        search_entry.grab_focus ();
    }

    public void handle_activated () {
        search_entry.grab_focus ();
    }
}
