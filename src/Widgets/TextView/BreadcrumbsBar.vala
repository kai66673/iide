public class Iide.BreadcrumbFileSegment : Gtk.Box {
    private GLib.File file;
    private bool is_file;
    private Gtk.MenuButton button;

    public BreadcrumbFileSegment (GLib.File file, bool is_file) {
        Object (orientation: Gtk.Orientation.HORIZONTAL, spacing: 0);

        this.file = file;
        this.is_file = is_file;

        button = new Gtk.MenuButton ();
        button.has_frame = false;
        button.can_focus = false;
        button.add_css_class ("flat");
        button.add_css_class ("small-menu-button");
        button.valign = Gtk.Align.CENTER;
        button.can_shrink = true;

        var label = new Gtk.Label (file.get_basename () + (is_file ? "" : " >"));
        button.set_child (label);
        label.set_ellipsize (Pango.EllipsizeMode.END);
        label.set_width_chars (1);
        button.always_show_arrow = false;

        if (is_file) {
            // В VSCode обычно иконка и текст вместе, можно использовать Box
            var btn_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4);
            var icon = new Gtk.Image.from_icon_name ("text-x-generic-symbolic");
            btn_box.append (icon);
            btn_box.append (label);
            button.set_child (btn_box);
        }

        this.append (button);

        if (!is_file) {
            setup_popover ();
        }
    }

    private void setup_popover () {
        var popover = new Gtk.Popover ();
        button.set_popover (popover);

        button.notify["active"].connect (() => {
            if (button.active) {
                var navigator = new BreadcrumbFileNavigator (this.file);

                popover.set_child (navigator);
                navigator.search_entry.set_key_capture_widget (popover);
            }
        });
    }
}

public class Iide.BreadcrumbsBar : Gtk.Box {
    private Gtk.Box path_box; // Относительный путь: Проект > src > main.vala
    private Gtk.Box scope_box; // LSP-структура: MyClass > my_method

    public BreadcrumbsBar () {
        Object (orientation: Gtk.Orientation.HORIZONTAL, spacing: 0);
        add_css_class ("breadcrumbs-bar");

        path_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
        path_box.height_request = 24;
        path_box.hexpand = false;
        path_box.halign = Gtk.Align.START;
        scope_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
        scope_box.height_request = 24;
        scope_box.hexpand = false;
        scope_box.halign = Gtk.Align.START;

        append (path_box);
        append (scope_box);
    }

    public void update_file_path (GLib.File file, GLib.File project_root) {
        var child = path_box.get_first_child ();
        while (child != null) {
            var next = child.get_next_sibling ();
            path_box.remove (child);
            child = next;
        }

        string relative_path = project_root.get_relative_path (file);

        var segment = new BreadcrumbFileSegment (file, true);
        path_box.append (segment);

        if (relative_path == null) {
            return;
        }

        var current_file = file.get_parent ();
        while (current_file.get_path () != project_root.get_path ()) {
            var dir_segment = new BreadcrumbFileSegment (current_file, false);
            path_box.prepend (dir_segment);
            current_file = current_file.get_parent ();
            if (current_file == null)
                break;
        }
    }
}