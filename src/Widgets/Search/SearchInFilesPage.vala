public class Iide.SearchInFilesPage : Gtk.Box, SearchPanelInterface {
    private Gtk.SearchEntry search_entry;
    private Gtk.ListView results_view;
    private Gtk.SingleSelection selection;
    private Iide.ProjectManager project_manager;
    private Iide.DocumentManager document_manager;
    private Window? parent_window;
    private string project_root_path;
    private string current_query;

    private Gtk.Stack status_stack;
    private Gtk.Spinner spinner;

    private uint debounce_id = 0;
    private bool content_loaded = false;

    private const int MAX_RESULTS = 100;

    public void focus_search_entry () {
        search_entry.grab_focus ();
    }

    private class MatchRange : Object {
        public int start { get; construct; }
        public int end { get; construct; }

        public MatchRange (int start, int end) {
            Object (start: start, end: end);
        }
    }

    private class SearchResult : Object {
        public string file_path { get; construct; }
        public string file_name { get; construct; }
        public string relative_path { get; construct; }
        public int line_number { get; construct; }
        public string line_content { get; construct; }
        public Gee.List<MatchRange> matches { get; construct; }
        public int score { get; construct; }

        public SearchResult (string file_path, string file_name, string relative_path, int line_number, string line_content, Gee.List<MatchRange> matches, int score = 0) {
            Object (
                    file_path: file_path,
                    file_name: file_name,
                    relative_path: relative_path,
                    line_number: line_number,
                    line_content: line_content,
                    matches: matches,
                    score: score
            );
        }
    }

    private Gee.List<SearchResult> all_results;
    private Gtk.StringList string_list;

    public SearchInFilesPage (Window parent_window, Iide.DocumentManager document_manager) {
        this.parent_window = parent_window;
        this.document_manager = document_manager;
        this.project_manager = Iide.ProjectManager.get_instance ();
        this.all_results = new Gee.ArrayList<SearchResult> ();

        var project_root = project_manager.get_current_project_root ();
        if (project_root != null) {
            this.project_root_path = project_root.get_path () ?? "";
        } else {
            this.project_root_path = "";
        }

        setup_ui ();

        project_manager.file_cache_updated.connect (on_file_cache_updated);
        project_manager.file_cache_invalidated.connect (on_file_cache_invalidated);
    }

    ~SearchInFilesPage () {
        project_manager.file_cache_updated.disconnect (on_file_cache_updated);
        project_manager.file_cache_invalidated.disconnect (on_file_cache_invalidated);
    }

    private void setup_ui () {
        var vbox = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
        vbox.margin_top = 12;
        vbox.margin_bottom = 12;
        vbox.margin_start = 12;
        vbox.margin_end = 12;

        search_entry = new Gtk.SearchEntry () {
            placeholder_text = _("Search text..."),
            hexpand = true
        };
        vbox.append (search_entry);

        var list_model = new Gtk.StringList (new string[0]);
        string_list = list_model;
        selection = new Gtk.SingleSelection (list_model);
        results_view = new Gtk.ListView (selection, null);
        results_view.hexpand = true;
        results_view.vexpand = true;
        results_view.show_separators = true;

        var factory = new Gtk.SignalListItemFactory ();
        factory.setup.connect ((item) => {
            var list_item = item as Gtk.ListItem;
            var item_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 2);
            item_box.margin_start = 8;
            item_box.margin_end = 8;
            item_box.margin_top = 4;
            item_box.margin_bottom = 4;

            var line_label = new Gtk.Label (null);
            line_label.xalign = 0;
            line_label.add_css_class ("monospace");
            line_label.add_css_class ("body");
            line_label.hexpand = true;
            line_label.selectable = true;

            var path_label = new Gtk.Label (null);
            path_label.xalign = 0;
            path_label.add_css_class ("dim-label");
            path_label.add_css_class ("caption");
            path_label.hexpand = true;

            item_box.append (line_label);
            item_box.append (path_label);
            list_item.set_child (item_box);
        });

        factory.bind.connect ((item) => {
            var list_item = item as Gtk.ListItem;
            var item_box = list_item.get_child () as Gtk.Box;
            var line_label = item_box.get_first_child () as Gtk.Label;
            var path_label = line_label.get_next_sibling () as Gtk.Label;

            var index = list_item.get_position ();
            if (index >= 0 && index < all_results.size) {
                var result = all_results[(int) index];
                var highlighted = highlight_matches (result.line_content, result.matches);
                line_label.set_markup ("%d: %s".printf (result.line_number + 1, highlighted));
                path_label.set_label ("%s".printf (result.relative_path));
            }
        });

        results_view.factory = factory;

        var scrolled = new Gtk.ScrolledWindow ();
        scrolled.child = results_view;
        scrolled.hexpand = true;
        scrolled.vexpand = true;

        status_stack = new Gtk.Stack ();
        status_stack.transition_type = Gtk.StackTransitionType.CROSSFADE;

        var loading_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 12);
        loading_box.valign = Gtk.Align.CENTER;
        loading_box.halign = Gtk.Align.CENTER;

        spinner = new Gtk.Spinner ();
        spinner.set_size_request (32, 32);

        var loading_label = new Gtk.Label (_("Indexing project files..."));
        loading_label.add_css_class ("dim-label");

        loading_box.append (spinner);
        loading_box.append (loading_label);

        status_stack.add_named (loading_box, "loading");
        status_stack.add_named (scrolled, "ready");

        vbox.append (status_stack);
        this.append (vbox);

        search_entry.changed.connect (on_search_changed);

        var key_controller = new Gtk.EventControllerKey ();
        key_controller.key_pressed.connect (on_key_pressed);
        search_entry.add_controller (key_controller);

        results_view.activate.connect (() => {
            open_selected ();
        });

        search_entry.activate.connect (() => {
            open_selected ();
        });

        search_entry.focus_on_click = false;
    }

    private bool is_text_file (string path) {
        var file = GLib.File.new_for_path (path);
        try {
            var info = file.query_info (FileAttribute.STANDARD_CONTENT_TYPE, FileQueryInfoFlags.NONE);
            string content_type = info.get_content_type ();
            return ContentType.is_a (content_type, "text/plain");
        } catch (Error e) {
            return false;
        }
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

    private bool on_key_pressed (Gtk.EventControllerKey controller, uint keyval, uint keycode, Gdk.ModifierType modifiers) {
        if (keyval == Gdk.Key.Escape) {
            close_requested ();
            return true;
        } else if (keyval == Gdk.Key.Return || keyval == Gdk.Key.KP_Enter) {
            open_selected ((modifiers & Gdk.ModifierType.SHIFT_MASK) == 0);
            return true;
        } else if (keyval == Gdk.Key.Up || keyval == Gdk.Key.KP_Up) {
            if (selection.selected > 0) {
                selection.selected -= 1;
                results_view.scroll_to (selection.selected, Gtk.ListScrollFlags.NONE, null);
            }
            return true;
        } else if (keyval == Gdk.Key.Down || keyval == Gdk.Key.KP_Down) {
            if (selection.selected < (int) string_list.get_n_items () - 1) {
                selection.selected += 1;
                results_view.scroll_to (selection.selected, Gtk.ListScrollFlags.NONE, null);
            }
            return true;
        }
        return false;
    }

    private void on_file_cache_updated () {
    }

    private void on_file_cache_invalidated () {
        all_results.clear ();
    }

    private void on_search_changed () {
        if (debounce_id > 0) {
            Source.remove (debounce_id);
            debounce_id = 0;
        }

        string query = search_entry.get_text ().strip ();

        if (query.length == 0 || query.length == 1) {
            all_results = new Gee.ArrayList<SearchResult> ();
            update_results ();
            return;
        }

        debounce_id = Timeout.add (200, () => {
            perform_search_async.begin ();
            debounce_id = 0;
            return false;
        });
    }

    private async void perform_search_async () {
        yield ensure_content_loaded ();
        perform_search ();
    }

    private async void ensure_content_loaded () {
        if (content_loaded) {
            return;
        }

        status_stack.visible_child_name = "loading";
        spinner.start ();

        yield project_manager.ensure_file_cache_async ();
        content_loaded = true;

        spinner.stop ();
        status_stack.visible_child_name = "ready";
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

    private int fuzzy_score (string target, string query) {
        if (target.length == 0 || query.length == 0) {
            return 0;
        }

        var target_lower = target.down ();
        var query_lower = query.down ();

        if (target_lower.contains (query_lower)) {
            var pos = target_lower.index_of (query_lower);
            if (pos == 0) {
                return 1000 + (1000 - target.length);
            }
            return 500 + (1000 - pos);
        }

        int score = 0;
        int consecutive = 0;
        int last_match = -1;
        bool prev_was_sep = true;
        bool matched_all = true;

        for (int qi = 0; qi < query_lower.length; qi++) {
            bool found = false;
            for (int idx = last_match + 1; idx < target_lower.length; idx++) {
                if (target_lower[idx] == query_lower[qi]) {
                    found = true;
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

            unichar c = last_match >= 0 && last_match < (int) target.length ? target[last_match] : ' ';
            prev_was_sep = !c.isalnum () && c != '_';
        }

        return matched_all ? score : 0;
    }

    private void perform_search () {
        current_query = search_entry.get_text ().strip ();

        if (current_query == "" || current_query.length < 2) {
            all_results = new Gee.ArrayList<SearchResult> ();
            update_results ();
            return;
        }

        var file_cache = project_manager.get_file_cache ();
        if (file_cache == null) {
            all_results = new Gee.ArrayList<SearchResult> ();
            update_results ();
            return;
        }

        var results = new Gee.ArrayList<SearchResult> ();
        var query_lower = current_query.down ();

        foreach (var file_entry in file_cache) {
            if (!is_text_file (file_entry.path)) {
                continue;
            }

            try {
                var file = GLib.File.new_for_path (file_entry.path);
                var dis = new DataInputStream (file.read ());
                string line;
                int line_num = 0;

                while ((line = dis.read_line ()) != null) {
                    var matches = new Gee.ArrayList<MatchRange> ();
                    int score = fuzzy_match_with_positions (line, current_query, matches);

                    if (score > 0) {
                        var stripped = line.strip ();
                        int offset = line.index_of (stripped);

                        var adjusted_matches = new Gee.ArrayList<MatchRange> ();
                        foreach (var m in matches) {
                            adjusted_matches.add (new MatchRange (m.start - offset, m.end - offset));
                        }

                        results.add (new SearchResult (
                            file_entry.path,
                            file_entry.name,
                            file_entry.relative_path,
                            line_num,
                            stripped,
                            adjusted_matches,
                            score
                        ));
                    }
                    line_num++;
                }
                dis.close ();
            } catch (Error e) {
            }
        }

        results.sort ((a, b) => b.score - a.score);

        all_results = new Gee.ArrayList<SearchResult> ();
        for (int i = 0; i < results.size && i < MAX_RESULTS; i++) {
            all_results.add (results[i]);
        }

        update_results ();
    }

    private void update_results () {
        var strings = new string[all_results.size];
        for (int i = 0; i < all_results.size; i++) {
            var result = all_results[i];
            strings[i] = "%d: %s".printf (result.line_number + 1, result.line_content);
        }

        string_list.splice (0, string_list.get_n_items (), strings);

        if (all_results.size > 0) {
            selection.selected = 0;
        }
    }

    private void open_selected (bool close_search = true) {
        var index = (int) selection.selected;
        if (index >= 0 && index < all_results.size) {
            var result = all_results[index];
            var file = GLib.File.new_for_path (result.file_path);

            int start_col = 0;
            int end_col = 0;
            if (result.matches != null && result.matches.size > 0) {
                start_col = result.matches[0].start;
                end_col = result.matches[0].end;
            }

            document_manager.open_document_with_selection (file, result.line_number, start_col, end_col, null);
            if (close_search) {
                close_requested ();
            }
        }
    }

    public void start_search (string query) {
        search_entry.set_text (query);
    }

    public void handle_activated () {
        status_stack.visible_child_name = "ready";
        search_entry.grab_focus ();

        perform_search_async.begin ();
    }
}