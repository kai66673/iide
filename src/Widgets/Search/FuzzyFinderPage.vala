public class Iide.FuzzyFinderPage : Gtk.Box, SearchPanelInterface {
    private Gtk.SearchEntry search_entry;
    private Gtk.ListView list_view;
    private Gtk.SingleSelection selection;
    private Gtk.StringList string_list;
    private Gee.List<FileEntry> all_files;
    private Gee.List<FileEntry> filtered_files;
    private Iide.ProjectManager project_manager;
    private Iide.DocumentManager document_manager;
    private Window? parent_window;

    private uint debounce_id = 0;

    private const int MAX_RESULTS = 50;

    public void focus_search_entry () {
        search_entry.grab_focus ();
    }

    private class FileEntry : Object {
        public string path { get; construct; }
        public string name { get; construct; }
        public string relative_path { get; construct; }
        public string display_name { get; construct; }

        public FileEntry (string path, string name, string relative_path) {
            Object (path: path, name: name, relative_path: relative_path, display_name: "%s  →  %s".printf (name, relative_path));
        }
    }

    public FuzzyFinderPage (Window parent_window, Iide.DocumentManager document_manager) {
        this.parent_window = parent_window;
        this.document_manager = document_manager;
        this.project_manager = Iide.ProjectManager.get_instance ();
        this.all_files = new Gee.ArrayList<FileEntry> ();
        this.filtered_files = new Gee.ArrayList<FileEntry> ();

        setup_ui ();
        load_project_files ();
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
            if (selection.selected > 0) {
                selection.selected -= 1;
                list_view.scroll_to (selection.selected, Gtk.ListScrollFlags.NONE, null);
            }
            return true;
        } else if (keyval == Gdk.Key.Down || keyval == Gdk.Key.KP_Down) {
            if (selection.selected < (int) string_list.get_n_items () - 1) {
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

        var factory = new Gtk.SignalListItemFactory ();
        factory.setup.connect ((item) => {
            var list_item = item as Gtk.ListItem;
            var item_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 2);
            item_box.margin_start = 6;
            item_box.margin_end = 6;
            item_box.margin_top = 6;
            item_box.margin_bottom = 6;

            var name_label = new Gtk.Label (null);
            name_label.xalign = 0;
            name_label.add_css_class ("title-5");
            name_label.hexpand = true;

            var path_label = new Gtk.Label (null);
            path_label.xalign = 0;
            path_label.add_css_class ("dim-label");
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
                name_label.set_label (entry.name);
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

    private void load_project_files () {
        var project_root = project_manager.get_current_project_root ();
        if (project_root == null) {
            return;
        }

        var root_path = project_root.get_path ();
        if (root_path == null) {
            return;
        }

        try {
            scan_directory (project_root, root_path);
        } catch (Error e) {
            warning ("Error scanning directory: %s", e.message);
        }

        all_files.sort ((a, b) => a.name.collate (b.name));
        perform_search ();
    }

    private void scan_directory (GLib.File dir, string base_path) throws Error {
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
                if (name == "node_modules" || name == "target" || name == "build" || name == "__pycache__") {
                    continue;
                }
                scan_directory (dir.get_child (name), base_path);
            } else if (file_type == FileType.REGULAR) {
                var path = dir.get_child (name).get_path ();
                if (path != null) {
                    var relative = path.substring (base_path.length + 1);
                    all_files.add (new FileEntry (path, name, relative));
                }
            }
        }
    }

    private void on_search_changed () {
        // 1. Сначала отменяем предыдущий таймер, если он был запущен
        if (debounce_id > 0) {
            Source.remove (debounce_id);
            debounce_id = 0;
        }

        // 2. Устанавливаем новый таймер (например, на 300 мс)
        debounce_id = Timeout.add (300, () => {
            perform_search ();

            // Возвращаем false, чтобы таймер не повторялся (однократное выполнение)
            debounce_id = 0;
            return false;
        });
    }

    private void perform_search () {
        var query = search_entry.get_text ().down ();
        filtered_files.clear ();

        if (query == "") {
            foreach (var f in all_files) {
                if (filtered_files.size >= MAX_RESULTS)break;
                filtered_files.add (f);
            }
        } else {
            foreach (var f in all_files) {
                if (fuzzy_match (f.name.down (), query)) {
                    filtered_files.add (f);
                    if (filtered_files.size >= MAX_RESULTS)break;
                }
            }
        }

        update_results ();
    }

    private bool fuzzy_match (string text, string query) {
        int qi = 0;
        for (int i = 0; i < text.length && qi < query.length; i++) {
            if (text[i] == query[qi]) {
                qi++;
            }
        }
        return qi == query.length;
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
            if (close_search)
                close_requested ();
        }
    }

    public override void show () {
        base.show ();
        search_entry.grab_focus ();
    }
}
