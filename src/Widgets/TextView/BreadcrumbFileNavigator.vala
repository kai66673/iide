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

    public signal void close_requested ();

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
                    this.refresh_state ();
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
        list_box.row_activated.connect ((row) => { open_or_select_row (row); });

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

        search_entry.search_changed.connect (() => {
            list_box.invalidate_filter ();
            select_first_visible_row ();
        });

        // Запускаем загрузку
        load_directory.begin (this.current_folder, (obj, res) => {
            load_directory.end (res);
            this.refresh_state ();
        });

        var key_controller = new Gtk.EventControllerKey ();
        key_controller.key_pressed.connect (on_key_pressed);
        search_entry.add_controller (key_controller);
        list_box.set_selection_mode (Gtk.SelectionMode.SINGLE);

        search_entry.activate.connect (() => {
            open_or_select_row (list_box.get_selected_row ());
        });
    }

    private void select_first_visible_row () {
        var row = list_box.get_first_child ();
        while (row != null) {
            var list_row = row as Gtk.ListBoxRow;
            if (list_row.get_child_visible ()) {
                list_box.select_row (list_row);
                break;
            }
            row = row.get_next_sibling ();
        }
    }

    private void refresh_state () {
        this.search_entry.grab_focus ();
        select_first_visible_row ();
    }

    private void open_or_select_row (Gtk.ListBoxRow? row) {
        if (row == null)
            return;

        var name = row.get_data<string> ("file-name");
        var type = row.get_data<GLib.FileType> ("file-type");
        var selected = current_folder.get_child (name);

        if (type == GLib.FileType.DIRECTORY) {
            // Переходим глубже
            load_directory.begin (selected, (obj, res) => {
                load_directory.end (res);
                this.current_folder = selected;
                this.search_entry.text = "";
                this.refresh_state ();
            });
        } else {
            open_file (selected);
        }
    }

    private bool on_key_pressed (Gtk.EventControllerKey controller, uint keyval, uint keycode, Gdk.ModifierType modifiers) {
        if (keyval == Gdk.Key.Escape) {
            close_requested ();
            return true;
        } else if (keyval == Gdk.Key.Up || keyval == Gdk.Key.KP_Up) {
            move_selection_up ();
            return true;
        } else if (keyval == Gdk.Key.Down || keyval == Gdk.Key.KP_Down) {
            move_selection_down ();
            return true;
        }
        return false;
    }

    private void move_selection_down () {
        var selected_row = list_box.get_selected_row ();
        if (selected_row == null) {
            select_first_visible_row ();
            return;
        }

        var next_row_widget = selected_row.get_next_sibling ();
        while (next_row_widget != null) {
            var list_row = next_row_widget as Gtk.ListBoxRow;
            if (list_row.get_child_visible ()) {
                list_box.select_row (list_row);
                return;
            }
            next_row_widget = next_row_widget.get_next_sibling ();
        }

        if (!selected_row.get_child_visible ())
            select_first_visible_row ();
    }

    private void move_selection_up () {
        var selected_row = list_box.get_selected_row ();
        if (selected_row == null) {
            select_first_visible_row ();
            return;
        }

        var prev_row_widget = selected_row.get_prev_sibling ();
        while (prev_row_widget != null) {
            var list_row = prev_row_widget as Gtk.ListBoxRow;
            if (list_row.get_child_visible ()) {
                list_box.select_row (list_row);
                return;
            }
            prev_row_widget = prev_row_widget.get_prev_sibling ();
        }

        if (!selected_row.get_child_visible ())
            select_first_visible_row ();
    }

    private async void load_directory (GLib.File folder) {
        stack.visible_child_name = "loading";
        list_box.remove_all ();
        back_button.sensitive = (folder.get_parent () != null);
        search_entry.placeholder_text = folder.get_basename ();

        try {
            var enumerator = yield folder.enumerate_children_async ("standard::name,standard::file-type",
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

        bool is_directory = info.get_file_type () == FileType.DIRECTORY;

        var icon = is_directory ? ImageFactory.folder_image () : ImageFactory.create_for_file_info (info);
        var label = new Gtk.Label (info.get_name ());
        label.ellipsize = Pango.EllipsizeMode.END;

        box.append (icon);
        box.append (label);

        // Если это папка, добавим стрелочку вправо, как в VSCode
        if (is_directory) {
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