public class Iide.SearchPage : Gtk.Box {
    private SearchEngine search_engine;

    private Gtk.SearchEntry search_entry;
    private SearchResultsView results_view;
    private Gtk.Stack status_stack;
    private Gtk.Spinner spinner;

    private GLib.Cancellable? search_cancellable = null;
    private uint debounce_id = 0;

    public signal void close_requested ();

    public SearchPage (SearchEngine search_engine) {
        Object (
                orientation : Gtk.Orientation.VERTICAL,
                spacing: 8,
                margin_top: 12,
                margin_bottom: 12,
                margin_start: 12,
                margin_end: 12
        );
        this.search_engine = search_engine;

        search_entry = new Gtk.SearchEntry () {
            placeholder_text = search_engine.search_entry_placeholder (),
            hexpand = true
        };
        this.append (search_entry);

        results_view = new SearchResultsView ();

        status_stack = new Gtk.Stack ();
        status_stack.transition_type = Gtk.StackTransitionType.CROSSFADE;

        var loading_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 12);
        loading_box.valign = Gtk.Align.CENTER;
        loading_box.halign = Gtk.Align.CENTER;

        spinner = new Gtk.Spinner ();
        spinner.set_size_request (32, 32);

        var loading_label = new Gtk.Label (search_engine.search_progress_message ());
        loading_label.add_css_class ("dim-label");

        loading_box.append (spinner);
        loading_box.append (loading_label);

        status_stack.add_named (loading_box, "loading");
        status_stack.add_named (results_view, "results");

        this.append (status_stack);

        status_stack.visible_child_name = "results";

        search_entry.search_changed.connect (on_search_changed);

        var key_controller = new Gtk.EventControllerKey ();
        key_controller.key_pressed.connect (on_key_pressed);
        search_entry.add_controller (key_controller);

        results_view.list_view.activate.connect (on_list_activated);
        search_entry.activate.connect (on_list_activated);
    }

    public string search_kind () {
        return search_engine.search_kind ();
    }

    public string search_title () {
        return search_engine.search_title ();
    }

    public string search_icon_name () {
        return search_engine.search_icon_name ();
    }

    public void handle_activated () {
        search_entry.grab_focus ();
    }

    private void on_list_activated () {
        open_selected ();
    }

    private void open_selected (bool close_search = true) {
        if (results_view.open_selected () && close_search) {
            close_requested ();
        }
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
            perform_search.begin (query);
            debounce_id = 0;
            return false;
        });
    }

    private async void perform_search (string query) {
        if (search_cancellable != null) {
            search_cancellable.cancel ();
        }
        search_cancellable = new GLib.Cancellable ();

        // ВКЛЮЧАЕМ ИНДИКАТОР ЗАГРУЗКИ
        status_stack.visible_child_name = "loading";
        spinner.start ();

        try {
            var results = yield search_engine.perform_search (query, search_cancellable);

            update_results (results);
        } catch (GLib.IOError.CANCELLED e) {
        } catch (GLib.Error e) {
            warning ("Search Error: %s", e.message);

            // ВЫКЛЮЧАЕМ ИНДИКАТОР ЗАГРУЗКИ
            status_stack.visible_child_name = "results";
            spinner.stop ();
        }
    }

    private void update_results (Gee.List<SearchResult>? new_results) {
        results_view.update_results (new_results);

        // ВЫКЛЮЧАЕМ ИНДИКАТОР ЗАГРУЗКИ
        spinner.stop ();
        status_stack.visible_child_name = "results";
    }
}