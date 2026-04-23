public class Iide.FuzzyFinderPage : Gtk.Box, SearchPanelInterface {
    private Gtk.SearchEntry search_entry;
    private SearchResultsView results_view;
    private Iide.ProjectManager project_manager;
    private Iide.DocumentManager document_manager;
    private Window? parent_window;

    private uint debounce_id = 0;
    private bool cache_loaded = false;
    private string current_query = "";
    private Gee.List<SearchResult> all_results;

    private const int MAX_RESULTS = 100;

    public void focus_search_entry () {
        search_entry.grab_focus ();
    }

    private int fuzzy_match_with_positions (string text, string query, Gee.List<MatchRange> matches) {
        if (text.length == 0 || query.length == 0) {
            return 0;
        }

        var text_lower = text.down ();
        var query_lower = query.down ();

        if (text_lower.contains (query_lower)) {
            var pos = text_lower.index_of (query_lower);
            matches.add (new MatchRange (pos, pos + (int) query_lower.length));
            if (pos == 0) {
                return 1000 + (1000 - text.length);
            }
            return 500 + (1000 - pos);
        }

        int score = 0;
        int consecutive = 0;
        int last_match = -1;
        bool prev_was_sep = true;
        bool matched_all = true;
        var match_positions = new Gee.ArrayList<int> ();

        for (int qi = 0; qi < query_lower.length; qi++) {
            bool found = false;
            for (int idx = last_match + 1; idx < text_lower.length; idx++) {
                if (text_lower[idx] == query_lower[qi]) {
                    found = true;
                    match_positions.add (idx);
                    last_match = idx;
                    consecutive++;

                    if (idx == 0 || prev_was_sep) {
                        score += 150;
                    } else if (consecutive > 1) {
                        score += consecutive * 10;
                    } else {
                        score += 15;
                    }
                    break;
                } else {
                    score -= 1;
                }
            }

            if (!found) {
                matched_all = false;
                break;
            }

            unichar c = last_match >= 0 && last_match < (int) text.length ? text[last_match] : ' ';
            prev_was_sep = !c.isalnum () && c != '_';
        }

        if (!matched_all) {
            return 0;
        }

        int i = 0;
        while (i < match_positions.size) {
            int start = match_positions[i];
            int end = start + 1;

            while (i + 1 < match_positions.size && match_positions[i + 1] == match_positions[i] + 1) {
                end = match_positions[i + 1] + 1;
                i++;
            }

            matches.add (new MatchRange (start, end));
            i++;
        }

        return score;
    }

    public FuzzyFinderPage (Window parent_window, Iide.DocumentManager document_manager) {
        this.parent_window = parent_window;
        this.document_manager = document_manager;
        this.project_manager = Iide.ProjectManager.get_instance ();

        this.all_results = new Gee.ArrayList<SearchResult> ();

        setup_ui ();

        project_manager.file_cache_updated.connect (on_file_cache_updated);
        project_manager.file_cache_invalidated.connect (on_file_cache_invalidated);
    }

    ~FuzzyFinderPage () {
        project_manager.file_cache_updated.disconnect (on_file_cache_updated);
        project_manager.file_cache_invalidated.disconnect (on_file_cache_invalidated);
    }

    public void handle_activated () {}

    private bool on_key_pressed (Gtk.EventControllerKey controller, uint keyval, uint keycode, Gdk.ModifierType modifiers) {
        if (keyval == Gdk.Key.Escape) {
            close_requested ();
            return true;
        } else if (keyval == Gdk.Key.Return || keyval == Gdk.Key.KP_Enter) {
            open_selected ((modifiers & Gdk.ModifierType.SHIFT_MASK) != 0);
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

    private void setup_ui () {
        var vbox = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
        vbox.margin_top = 12;
        vbox.margin_bottom = 12;
        vbox.margin_start = 12;
        vbox.margin_end = 12;

        search_entry = new Gtk.SearchEntry () {
            placeholder_text = _("Search files..."),
            hexpand = true
        };
        vbox.append (search_entry);

        results_view = new SearchResultsView ();

        vbox.append (results_view);
        append (vbox);

        search_entry.changed.connect (on_search_changed);

        var key_controller = new Gtk.EventControllerKey ();
        key_controller.key_pressed.connect (on_key_pressed);
        search_entry.add_controller (key_controller);

        results_view.list_view.activate.connect (() => {
            open_selected ();
        });

        search_entry.activate.connect (() => {
            open_selected ();
        });
    }

    private void on_file_cache_updated () {
        cache_loaded = true;
        perform_search ();
    }

    private void on_file_cache_invalidated () {
        cache_loaded = false;
        project_manager.ensure_file_cache_async.begin ();
    }

    private async void ensure_cache () {
        if (cache_loaded) {
            return;
        }
        yield project_manager.ensure_file_cache_async ();

        cache_loaded = true;
    }

    private void on_search_changed () {
        if (debounce_id > 0) {
            Source.remove (debounce_id);
            debounce_id = 0;
        }

        debounce_id = Timeout.add (100, () => {
            perform_search_async.begin ();
            debounce_id = 0;
            return false;
        });
    }

    private async void perform_search_async () {
        yield ensure_cache ();

        perform_search ();
    }

    private void perform_search () {
        var cache = project_manager.get_file_cache ();
        if (cache == null) {
            all_results.clear ();
            update_results ();
            return;
        }

        current_query = search_entry.get_text ();
        var query = current_query.down ();
        all_results.clear ();

        if (query == "") {
            foreach (var f in cache) {
                if (all_results.size >= MAX_RESULTS)break;
                all_results.add (new SearchResult (f.path,
                                                   f.relative_path,
                                                   -1,
                                                   f.name,
                                                   new Gee.ArrayList<MatchRange> ()));
            }
        } else {
            foreach (var f in cache) {
                var matches = new Gee.ArrayList<MatchRange> ();
                int score = fuzzy_match_with_positions (f.name.down (), query, matches);

                if (score > 20) {
                    all_results.add (new SearchResult (f.path,
                                                       f.relative_path,
                                                       -1,
                                                       f.name,
                                                       matches,
                                                       null,
                                                       score));
                    if (all_results.size >= MAX_RESULTS)break;
                }
            }
        }

        all_results.sort ((a, b) => b.score - a.score);
        update_results ();
    }

    private void update_results () {
        results_view.update_results (all_results);
    }

    private void open_selected (bool close_search = true) {
        var index = (int) results_view.selection.selected;
        if (index >= 0 && index < all_results.size) {
            var entry = all_results[index];
            var file = GLib.File.new_for_path (entry.file_path);
            document_manager.open_document (file, null);
            if (close_search) {
                close_requested ();
            }
        }
    }

    public override void show () {
        base.show ();
        search_entry.grab_focus ();
    }
}
