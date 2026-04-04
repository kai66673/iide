public class Iide.SearchInFilesDialog : Adw.Window {
    private Gtk.Entry search_entry;
    private Gtk.ListView results_view;
    private Gtk.SingleSelection selection;
    private Iide.ProjectManager project_manager;
    private Iide.DocumentManager document_manager;
    private Window? parent_window;
    private string project_root_path;
    private string current_query;

    private const int MAX_RESULTS = 200;

    private interface ListItem : Object {
        public abstract string get_display_text ();
        public abstract bool is_header ();
    }

    private class SearchResult : Object, ListItem {
        public string file_path { get; construct; }
        public string file_name { get; construct; }
        public string relative_path { get; construct; }
        public int line_number { get; construct; }
        public string line_content { get; construct; }
        public int match_start { get; construct; }
        public int match_end { get; construct; }

        public SearchResult (string file_path, string file_name, string relative_path, int line_number, string line_content, int match_start, int match_end) {
            Object (
                    file_path: file_path,
                    file_name: file_name,
                    relative_path: relative_path,
                    line_number: line_number,
                    line_content: line_content,
                    match_start: match_start,
                    match_end: match_end
            );
        }

        public string get_display_text () {
            return "%d: %s".printf (line_number + 1, line_content);
        }

        public bool is_header () {
            return false;
        }
    }

    private class ResultGroup : Object, ListItem {
        public string file_path { get; construct; }
        public string file_name { get; construct; }
        public string relative_path { get; construct; }
        public int result_count { get; construct; }

        public ResultGroup (string file_path, string file_name, string relative_path, int result_count) {
            Object (
                    file_path: file_path,
                    file_name: file_name,
                    relative_path: relative_path,
                    result_count: result_count
            );
        }

        public string get_display_text () {
            return relative_path;
        }

        public bool is_header () {
            return true;
        }
    }

    private Gee.List<ListItem> all_items;
    private Gee.List<ListItem> filtered_items;
    private Gtk.StringList string_list;

    public SearchInFilesDialog (Window parent_window, Iide.DocumentManager document_manager) {
        Object (
                title: _("Search in Files"),
                modal: true,
                destroy_with_parent: true,
                default_width: 800,
                default_height: 500
        );

        this.parent_window = parent_window;
        this.document_manager = document_manager;
        this.project_manager = Iide.ProjectManager.get_instance ();
        this.all_items = new Gee.ArrayList<ListItem> ();
        this.filtered_items = new Gee.ArrayList<ListItem> ();

        var project_root = project_manager.get_current_project_root ();
        if (project_root != null) {
            this.project_root_path = project_root.get_path () ?? "";
        } else {
            this.project_root_path = "";
        }

        setup_ui ();
    }

    private void setup_ui () {
        var vbox = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
        vbox.margin_top = 12;
        vbox.margin_bottom = 12;
        vbox.margin_start = 12;
        vbox.margin_end = 12;

        search_entry = new Gtk.Entry () {
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
            list_item.set_child (new Gtk.Label (null));
        });
        factory.bind.connect ((item) => {
            var list_item = item as Gtk.ListItem;
            var label = list_item.get_child () as Gtk.Label;
            var index = list_item.get_position ();

            if (index >= 0 && index < filtered_items.size) {
                var list_item_obj = filtered_items[(int) index];
                if (list_item_obj.is_header ()) {
                    var group = list_item_obj as ResultGroup;
                    label.set_label ("%s (%d)".printf (group.relative_path, group.result_count));
                    label.add_css_class ("title-5");
                    label.add_css_class ("dim-label");
                    label.xalign = 0;
                } else {
                    label.set_label (list_item_obj.get_display_text ());
                    label.add_css_class ("monospace");
                    label.add_css_class ("body");
                    label.xalign = 0;
                }
            }
        });
        results_view.factory = factory;

        var scrolled = new Gtk.ScrolledWindow ();
        scrolled.child = results_view;
        scrolled.hexpand = true;
        scrolled.vexpand = true;
        vbox.append (scrolled);

        set_content (vbox);

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

        this.set_default_widget (search_entry);
    }

    private bool on_key_pressed (Gtk.EventControllerKey controller, uint keyval, uint keycode, Gdk.ModifierType modifiers) {
        if (keyval == Gdk.Key.Escape) {
            this.close ();
            return true;
        } else if (keyval == Gdk.Key.Return || keyval == Gdk.Key.KP_Enter) {
            open_selected ();
            return true;
        } else if (keyval == Gdk.Key.Up || keyval == Gdk.Key.KP_Up) {
            navigate_up ();
            return true;
        } else if (keyval == Gdk.Key.Down || keyval == Gdk.Key.KP_Down) {
            navigate_down ();
            return true;
        }
        return false;
    }

    private void navigate_up () {
        var current = (int) selection.selected;
        if (current <= 0)return;

        for (int i = current - 1; i >= 0; i--) {
            if (filtered_items[i] is SearchResult) {
                selection.selected = i;
                results_view.scroll_to (i, Gtk.ListScrollFlags.NONE, null);
                return;
            }
        }
    }

    private void navigate_down () {
        var current = (int) selection.selected;
        var max = (int) string_list.get_n_items () - 1;
        if (current >= max)return;

        for (int i = current + 1; i < filtered_items.size; i++) {
            if (filtered_items[i] is SearchResult) {
                selection.selected = i;
                results_view.scroll_to (i, Gtk.ListScrollFlags.NONE, null);
                return;
            }
        }
    }

    private void on_search_changed () {
        current_query = search_entry.get_text ();

        if (current_query == "" || current_query.length < 2) {
            filtered_items = new Gee.ArrayList<ListItem> ();
            update_results ();
            return;
        }

        var query_lower = current_query.down ();
        var results_by_file = new Gee.HashMap<string, Gee.List<SearchResult>> ();

        foreach (var item in all_items) {
            if (item is ResultGroup) {
                continue;
            }
            var result = item as SearchResult;
            if (result.line_content.down ().contains (query_lower)) {
                if (!results_by_file.has_key (result.file_path)) {
                    results_by_file[result.file_path] = new Gee.ArrayList<SearchResult> ();
                }
                results_by_file[result.file_path].add (result);
            }
        }

        filtered_items = new Gee.ArrayList<ListItem> ();
        foreach (var entry in results_by_file) {
            if (filtered_items.size >= MAX_RESULTS)break;

            var group = new ResultGroup (
                                         entry.key,
                                         entry.value[0].file_name,
                                         entry.value[0].relative_path,
                                         entry.value.size
            );
            filtered_items.add (group);

            foreach (var result in entry.value) {
                if (filtered_items.size >= MAX_RESULTS)break;
                filtered_items.add (result);
            }
        }

        update_results ();
    }

    private void update_results () {
        var strings = new string[filtered_items.size];
        for (int i = 0; i < filtered_items.size; i++) {
            strings[i] = filtered_items[i].get_display_text ();
        }

        string_list.splice (0, string_list.get_n_items (), strings);

        if (filtered_items.size > 0) {
            select_first_result ();
        }
    }

    private void select_first_result () {
        for (int i = 0; i < filtered_items.size; i++) {
            if (filtered_items[i] is SearchResult) {
                selection.selected = i;
                return;
            }
        }
    }

    private void open_selected () {
        var index = (int) selection.selected;
        if (index >= 0 && index < filtered_items.size) {
            var item = filtered_items[index];
            if (item is SearchResult) {
                var result = item as SearchResult;
                var file = GLib.File.new_for_path (result.file_path);

                var query_lower = current_query.down ();
                var line_lower = result.line_content.down ();
                var pos = line_lower.index_of (query_lower);
                var start_col = pos >= 0 ? pos : 0;
                var end_col = pos >= 0 ? pos + (int) current_query.length : start_col;

                document_manager.open_document_with_selection (file, parent_window, result.line_number, start_col, end_col, null);
                this.close ();
            }
        }
    }

    public void start_search (string query) {
        search_entry.set_text (query);
    }

    private void scan_files_for_search () {
        if (project_root_path == "") {
            return;
        }

        try {
            scan_directory (GLib.File.new_for_path (project_root_path));
        } catch (Error e) {
            warning ("Error scanning for search: %s", e.message);
        }

        on_search_changed ();
    }

    private void scan_directory (GLib.File dir) throws Error {
        var enumerator = dir.enumerate_children (
                                                 "standard::name,standard::type",
                                                 FileQueryInfoFlags.NONE,
                                                 null
        );

        FileInfo? info;
        while ((info = enumerator.next_file (null)) != null) {
            var name = info.get_name ();
            if (name.has_prefix (".")) {
                continue;
            }

            var file_type = info.get_file_type ();
            if (file_type == FileType.DIRECTORY) {
                if (name == "node_modules" || name == "target" || name == "build" ||
                    name == "__pycache__" || name == ".git") {
                    continue;
                }
                scan_directory (dir.get_child (name));
            } else if (file_type == FileType.REGULAR) {
                var path = dir.get_child (name).get_path ();
                if (path != null) {
                    search_file (path);
                }
            }
        }
    }

    private void search_file (string file_path) {
        try {
            var file = GLib.File.new_for_path (file_path);
            var dis = new DataInputStream (file.read ());
            string line;
            int line_num = 0;

            string relative_path = file_path;
            if (file_path.has_prefix (project_root_path)) {
                relative_path = file_path.substring (project_root_path.length);
                if (relative_path.has_prefix ("/")) {
                    relative_path = relative_path.substring (1);
                }
            }

            while ((line = dis.read_line ()) != null) {
                all_items.add (new SearchResult (
                                                 file_path,
                                                 file.get_basename (),
                                                 relative_path,
                                                 line_num,
                                                 line.strip (),
                                                 0, 0
                ));
                line_num++;
            }
            dis.close ();
        } catch (Error e) {
        }
    }

    public override void show () {
        base.show ();
        if (all_items.size == 0) {
            scan_files_for_search ();
        }
        search_entry.grab_focus ();
    }
}
