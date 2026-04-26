public class Iide.BreadcrumbFileSegment : Gtk.Box {
    private GLib.File file;
    private bool is_file;
    private Gtk.MenuButton button;
    private SourceView source_view;

    public signal void breadcrumb_clicked (uint line, uint column);

    public BreadcrumbFileSegment (SourceView source_view, GLib.File file, bool is_file) {
        Object (orientation: Gtk.Orientation.HORIZONTAL, spacing: 0);
        this.source_view = source_view;

        this.file = file;
        this.is_file = is_file;

        button = new Gtk.MenuButton ();
        button.has_frame = false;
        button.add_css_class ("flat");
        button.add_css_class ("small-menu-button");
        button.valign = Gtk.Align.CENTER;
        button.can_shrink = true;
        button.always_show_arrow = true;

        var label = new Gtk.Label (file.get_basename ());
        button.set_child (label);
        label.set_ellipsize (Pango.EllipsizeMode.END);
        label.set_width_chars (1);

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
        } else if (source_view.ts_highlighter != null) {
            setup_file_outline_popover ();
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

    private void setup_file_outline_popover () {
        var popover = new Gtk.Popover ();
        button.set_popover (popover);

        button.notify["active"].connect (() => {
            if (button.active) {
                // Получаем ПОЛНОЕ дерево символов из хайлайтера/LSP
                var outline = source_view.ts_highlighter.get_full_outline ();
                var navigator = new BreadcrumbSymbolOutlineNavigator (outline);

                popover.set_child (navigator);
                navigator.search_entry.set_key_capture_widget (popover);

                navigator.breadcrumb_clicked.connect ((line, column) => {
                    button.active = false;
                    breadcrumb_clicked (line, column);
                });
            }
        });
    }
}

public class Iide.BreadcrumbSymbolSegment : Gtk.Box {
    private Gtk.MenuButton button;
    private BreadcrumbItem current_item;

    public signal void breadcrumb_clicked (uint line, uint column);

    public BreadcrumbSymbolSegment (BreadcrumbItem item) {
        Object (orientation: Gtk.Orientation.HORIZONTAL, spacing: 0);
        this.current_item = item;

        button = new Gtk.MenuButton ();
        button.has_frame = false;
        button.add_css_class ("flat");
        button.add_css_class ("small-menu-button");
        button.valign = Gtk.Align.CENTER;
        button.can_shrink = true;
        button.always_show_arrow = true;

        var label = new Gtk.Label (item.name);
        button.set_child (label);
        label.set_ellipsize (Pango.EllipsizeMode.END);
        label.set_width_chars (1);

        this.append (button);
        setup_popover ();
    }

    private void setup_popover () {
        var popover = new Gtk.Popover ();
        button.set_popover (popover);

        button.notify["active"].connect (() => {
            if (button.active) {
                var navigator = new BreadcrumbTreeSitterNavigator (this.current_item.siblings);
                popover.set_child (navigator);

                // Используем ваш проверенный метод для фокуса
                navigator.search_entry.set_key_capture_widget (popover);

                navigator.breadcrumb_clicked.connect ((line, column) => {
                    button.active = false;
                    this.breadcrumb_clicked (line, column);
                });
            }
        });
    }
}

public class Iide.BreadcrumbsBar : Gtk.Box {
    private Gtk.Box path_box; // Относительный путь: Проект > src > main.vala
    private Gtk.Box scope_box; // LSP-структура: MyClass > my_method
    private SourceView source_view;

    public signal void breadcrumb_clicked (uint line, uint column);

    public BreadcrumbsBar (SourceView source_view) {
        Object (orientation: Gtk.Orientation.HORIZONTAL, spacing: 0);
        this.source_view = source_view;
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

        var segment = new BreadcrumbFileSegment (source_view, file, true);
        path_box.append (segment);
        segment.breadcrumb_clicked.connect ((line, column) => {
            breadcrumb_clicked (line, column);
        });

        if (relative_path == null) {
            return;
        }

        var current_file = file.get_parent ();
        while (current_file.get_path () != project_root.get_path ()) {
            var dir_segment = new BreadcrumbFileSegment (source_view, current_file, false);
            path_box.prepend (dir_segment);
            current_file = current_file.get_parent ();
            if (current_file == null)
                break;
        }
    }

    public void update_breadcrumbs (Gee.List<BreadcrumbItem?> crumbs) {
        // Очистка контейнера
        var child = scope_box.get_first_child ();
        while (child != null) {
            var next = child.get_next_sibling ();
            scope_box.remove (child);
            child = next;
        }

        foreach (var crumb in crumbs) {
            var ts_segment = new BreadcrumbSymbolSegment (crumb);
            scope_box.append (ts_segment);
            ts_segment.breadcrumb_clicked.connect ((line, column) => {
                breadcrumb_clicked (line, column);
            });
        }
    }
}