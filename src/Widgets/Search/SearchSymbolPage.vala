public class Iide.SearchSymbolPage : Gtk.Box, SearchPanelInterface {
    private Gtk.SearchEntry search_entry;
    private SearchResultsView results_view;
    private Gtk.Stack status_stack;
    private Gtk.Spinner spinner;

    private GLib.Cancellable? search_cancellable = null;
    private uint debounce_id = 0;

    private Iide.DocumentManager document_manager;

    private const int MAX_RESULTS = 100;

    public SearchSymbolPage (Iide.DocumentManager document_manager) {
        this.document_manager = document_manager;

        setup_ui ();
    }

    private void setup_ui () {
        var vbox = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
        vbox.margin_top = 12;
        vbox.margin_bottom = 12;
        vbox.margin_start = 12;
        vbox.margin_end = 12;

        search_entry = new Gtk.SearchEntry () {
            placeholder_text = _("Search functions, classes, variables (min 3 chars)..."),
            hexpand = true
        };
        vbox.append (search_entry);

        results_view = new SearchResultsView ();

        status_stack = new Gtk.Stack ();
        status_stack.transition_type = Gtk.StackTransitionType.CROSSFADE;

        var loading_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 12);
        loading_box.valign = Gtk.Align.CENTER;
        loading_box.halign = Gtk.Align.CENTER;

        spinner = new Gtk.Spinner ();
        spinner.set_size_request (32, 32);

        var loading_label = new Gtk.Label (_("Searching symbols..."));
        loading_label.add_css_class ("dim-label");

        loading_box.append (spinner);
        loading_box.append (loading_label);

        status_stack.add_named (results_view, "results");
        status_stack.add_named (loading_box, "loading");

        vbox.append (status_stack);
        this.append (vbox);

        status_stack.visible_child_name = "results";

        search_entry.search_changed.connect (on_search_changed);

        var key_controller = new Gtk.EventControllerKey ();
        key_controller.key_pressed.connect (on_key_pressed);
        search_entry.add_controller (key_controller);

        results_view.list_view.activate.connect (on_list_activated);
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
            results_view.select_up ();
            return true;
        } else if (keyval == Gdk.Key.Down || keyval == Gdk.Key.KP_Down) {
            results_view.select_down ();
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
            results_view.update_results (null);
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

    private void update_results_list (Gee.List<LspSymbol>? new_results) {
        if (new_results == null || new_results.size == 0) {
            results_view.update_results (null);
            status_stack.visible_child_name = "results";
            return;
        }

        var show_count = new_results.size;
        if (show_count > MAX_RESULTS) {
            show_count = MAX_RESULTS;
        }

        var items = new SearchResult[show_count];
        for (var i = 0; i < show_count; i++) {
            var sym = new_results[i];
            var file_path = sym.uri.replace ("file://", "");
            items[i] = new SearchResult (
                                         file_path,
                                         file_path,
                                         sym.start_line,
                                         sym.name,
                                         null,
                                         sym.kind.to_icon_name ()
            );
        }

        results_view.update_result_list (items);
        status_stack.visible_child_name = "results";
    }

    private void on_list_activated () {
        open_selected ();
    }

    private void on_entry_activated () {
        open_selected ();
    }

    private void open_selected (bool close_search = true) {
        if (results_view.open_selected () && close_search) {
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
