public class Iide.BreadcrumbFileNavigator : Gtk.Box {
    private GLib.File root_file;
    private GLib.File current_folder;

    public Gtk.SearchEntry search_entry;
    private Gtk.Button back_button;
    private Gtk.ListBox list_box;
    private Gtk.ScrolledWindow scrolled;
    private Gtk.Stack stack;

    private void open_file (GLib.File file) {
        DocumentManager.get_instance ().open_document (file, null);
    }

    public BreadcrumbFileNavigator (GLib.File file) {
        Object (orientation: Gtk.Orientation.VERTICAL, spacing: 6);
        this.root_file = file;
        this.current_folder = file;
        this.set_size_request (300, -1);
        this.margin_top = this.margin_bottom = this.margin_start = this.margin_end = 6;

        // --- Header ---
        var header = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4);

        back_button = new Gtk.Button.from_icon_name ("go-previous-symbolic");
        back_button.add_css_class ("flat");
        back_button.clicked.connect (() => {
            var parent = current_folder.get_parent ();
            if (parent != null)
                load_directory.begin (parent, (obj, res) => {
                    load_directory.end (res);
                    this.current_folder = parent;
                    this.search_entry.text = "";
                });
        });

        search_entry = new Gtk.SearchEntry ();
        search_entry.hexpand = true;
        search_entry.focusable = true; // Критично для фокуса

        header.append (back_button);
        header.append (search_entry);
        this.append (header);

        // --- Stack для переключения между загрузкой и списком ---
        stack = new Gtk.Stack ();
        stack.transition_type = Gtk.StackTransitionType.CROSSFADE;

        var spinner = new Gtk.Spinner ();
        spinner.start ();
        stack.add_named (spinner, "loading");

        list_box = new Gtk.ListBox ();
        list_box.add_css_class ("navigation-sidebar");
        list_box.row_activated.connect ((row) => {
            var name = row.get_data<string> ("file-name");
            var type = row.get_data<GLib.FileType> ("file-type");
            var selected = current_folder.get_child (name);

            if (type == GLib.FileType.DIRECTORY) {
                // Переходим глубже
                load_directory.begin (selected, (obj, res) => {
                    load_directory.end (res);
                    this.current_folder = selected;
                    this.search_entry.text = "";
                });
            } else {
                open_file (selected);
            }
        });

        list_box.set_filter_func ((row) => {
            var text = search_entry.get_text ().down ();
            if (text == "")return true;
            var name = row.get_data<string> ("file-name").down ();
            return name.contains (text);
        });

        scrolled = new Gtk.ScrolledWindow ();
        scrolled.propagate_natural_height = true;
        scrolled.set_min_content_height (0);
        scrolled.set_max_content_height (400);
        scrolled.set_child (list_box);
        stack.add_named (scrolled, "list");

        this.append (stack);

        search_entry.search_changed.connect (() => { list_box.invalidate_filter (); });

        // Запускаем загрузку
        load_directory.begin (this.current_folder);
    }

    private async void load_directory (GLib.File folder) {
        stack.visible_child_name = "loading";
        list_box.remove_all ();
        back_button.sensitive = (folder.get_parent () != null);
        search_entry.placeholder_text = folder.get_basename ();

        try {
            var enumerator = yield folder.enumerate_children_async ("standard::name,standard::icon,standard::file-type",
                GLib.FileQueryInfoFlags.NONE, GLib.Priority.DEFAULT, null);

            while (true) {
                var files = yield enumerator.next_files_async (50, GLib.Priority.DEFAULT, null);

                if (files == null)break;
                foreach (var info in files) {
                    list_box.append (create_row (info));
                }
            }
            stack.visible_child_name = "list";
        } catch (Error e) {
            stack.add_named (new Gtk.Label (e.message), "error");
            stack.visible_child_name = "error";
        }
    }

    private Gtk.ListBoxRow create_row (GLib.FileInfo info) {
        var row = new Gtk.ListBoxRow ();
        var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
        box.margin_start = box.margin_end = 8;
        box.margin_top = box.margin_bottom = 4;

        var icon = new Gtk.Image.from_gicon (info.get_icon ());
        var label = new Gtk.Label (info.get_name ());
        label.ellipsize = Pango.EllipsizeMode.END;

        box.append (icon);
        box.append (label);

        // Если это папка, добавим стрелочку вправо, как в VSCode
        if (info.get_file_type () == GLib.FileType.DIRECTORY) {
            var arrow = new Gtk.Image.from_icon_name ("go-next-symbolic");
            arrow.halign = Gtk.Align.END;
            arrow.hexpand = true;
            arrow.opacity = 0.5;
            box.append (arrow);
        }

        row.set_child (box);
        row.set_data ("file-name", info.get_name ());
        row.set_data ("file-type", info.get_file_type ());
        return row;
    }
}