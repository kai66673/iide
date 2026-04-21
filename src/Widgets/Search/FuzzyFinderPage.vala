public class Iide.FuzzyFinderPage : Gtk.Box, SearchPanelInterface {
    private Gtk.SearchEntry search_entry;
    private Gtk.ListView list_view;
    private Gtk.SingleSelection selection;
    private Gtk.StringList string_list;
    private Gee.List<Iide.FileEntry> filtered_files;
    private Iide.ProjectManager project_manager;
    private Iide.DocumentManager document_manager;
    private Window? parent_window;

    private uint debounce_id = 0;
    private bool cache_loaded = false;
    private string current_query = "";
    private Gee.List<Gee.List<MatchRange>> filtered_matches;

    private const int MAX_RESULTS = 50;

    private class MatchRange : Object {
        public int start { get; construct; }
        public int end { get; construct; }

        public MatchRange (int start, int end) {
            Object (start: start, end: end);
        }
    }

    public void focus_search_entry () {
        search_entry.grab_focus ();
    }

    private string escape_pango (string text) {
        return text
                .replace ("&", "&amp;")
                .replace ("<", "&lt;")
                .replace (">", "&gt;");
    }

    private string highlight_matches (string text, Gee.List<MatchRange> matches) {
        var escaped = escape_pango (text);

        if (matches == null || matches.size == 0) {
            return escaped;
        }

        var sb = new StringBuilder ();
        int pos = 0;

        foreach (var m in matches) {
            if (m.start > pos) {
                sb.append (escaped.substring (pos, m.start - pos));
            }
            if (m.end > m.start && m.end <= (int) escaped.length) {
                sb.append ("<span weight=\"bold\" background=\"#ffd700\" color=\"#000000\">");
                sb.append (escaped.substring (m.start, m.end - m.start));
                sb.append ("</span>");
            }
            pos = m.end;
        }

        if (pos < (int) escaped.length) {
            sb.append (escaped.substring (pos));
        }

        return sb.str;
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
        this.filtered_files = new Gee.ArrayList<Iide.FileEntry> ();
        this.filtered_matches = new Gee.ArrayList<Gee.List<MatchRange>> ();

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
            if (selection.selected > 0 && string_list != null) {
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

        string_list = new Gtk.StringList (new string[0]);
        selection = new Gtk.SingleSelection (string_list);
        list_view = new Gtk.ListView (selection, null);
        list_view.hexpand = true;
        list_view.vexpand = true;
        list_view.show_separators = true;

        var factory = new Gtk.SignalListItemFactory ();
        factory.setup.connect ((item) => {
            var list_item = item as Gtk.ListItem;
            var item_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 2);
            item_box.margin_start = 8;
            item_box.margin_end = 8;
            item_box.margin_top = 6;
            item_box.margin_bottom = 6;

            var name_label = new Gtk.Label (null);
            name_label.xalign = 0;
            name_label.add_css_class ("title-5");
            name_label.hexpand = true;

            var path_label = new Gtk.Label (null);
            path_label.xalign = 0;
            path_label.add_css_class ("dim-label");
            path_label.add_css_class ("caption");
            path_label.hexpand = true;

            item_box.append (name_label);
            item_box.append (path_label);
            list_item.set_child (item_box);
        });
        factory.bind.connect ((item) => {
            var list_item = item as Gtk.ListItem;
            var item_box = list_item.get_child () as Gtk.Box;
            var name_label = item_box.get_first_child () as Gtk.Label;
            var path_label = name_label.get_next_sibling () as Gtk.Label;

            var index = list_item.get_position ();
            if (index >= 0 && index < filtered_files.size) {
                var entry = filtered_files[(int) index];
                var matches = filtered_matches.size > index ? filtered_matches[(int) index] : null;
                var highlighted_name = highlight_matches (entry.name, matches);
                name_label.set_markup (highlighted_name);
                path_label.set_label (entry.relative_path);
            }
        });
        list_view.factory = factory;

        var scrolled = new Gtk.ScrolledWindow ();
        scrolled.child = list_view;
        scrolled.hexpand = true;
        scrolled.vexpand = true;
        vbox.append (scrolled);

        append (vbox);

        search_entry.changed.connect (on_search_changed);

        var key_controller = new Gtk.EventControllerKey ();
        key_controller.key_pressed.connect (on_key_pressed);
        search_entry.add_controller (key_controller);

        list_view.activate.connect (() => {
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
            filtered_files.clear ();
            filtered_matches.clear ();
            update_results ();
            return;
        }

        current_query = search_entry.get_text ();
        var query = current_query.down ();
        filtered_files.clear ();
        filtered_matches.clear ();

        if (query == "") {
            foreach (var f in cache) {
                if (filtered_files.size >= MAX_RESULTS)break;
                filtered_files.add (f);
                filtered_matches.add (new Gee.ArrayList<MatchRange> ());
            }
        } else {
            foreach (var f in cache) {
                var matches = new Gee.ArrayList<MatchRange> ();
                int score = fuzzy_match_with_positions (f.name.down (), query, matches);

                if (score > 0) {
                    filtered_files.add (f);
                    filtered_matches.add (matches);
                    if (filtered_files.size >= MAX_RESULTS)break;
                }
            }
        }

        update_results ();
    }

    private void update_results () {
        var strings = new string[filtered_files.size];
        for (int i = 0; i < filtered_files.size; i++) {
            strings[i] = filtered_files[i].display_name;
        }

        string_list.splice (0, string_list.get_n_items (), strings);

        if (filtered_files.size > 0) {
            selection.selected = 0;
        }
    }

    private void open_selected (bool close_search = true) {
        var index = (int) selection.selected;
        if (index >= 0 && index < filtered_files.size) {
            var entry = filtered_files[index];
            var file = GLib.File.new_for_path (entry.path);
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
