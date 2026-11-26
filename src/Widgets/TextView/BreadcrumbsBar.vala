public class Iide.BreadcrumbFileSegment : Gtk.Box {
    private GLib.File file;
    private bool is_file;
    private Gtk.MenuButton button;
    private SourceView source_view;

    // popover владеет button; поле нужно, чтобы обработчик не захватывал
    // локальную переменную strong-блоком (пинновал сегмент и весь редактор)
    private unowned Gtk.Popover? popover = null;

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

        if (is_file) {
            // У VSCode обычно иконка и текст вместе. ВАЖНО: label должен попасть
            // в button ровно один раз и сразу внутри btn_box — раньше label сначала
            // становился child у button, а затем append в btn_box падал
            // с 'gtk_box_append: parent != NULL' и сегмент рендерился криво.
            var btn_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4);
            var icon = new Gtk.Image.from_icon_name ("text-x-generic-symbolic");
            btn_box.append (icon);
            btn_box.append (label);
            button.set_child (btn_box);
        } else {
            button.set_child (label);
        }

        this.append (button);

        if (!is_file) {
            setup_popover ();
        } else {
            setup_file_outline_popover ();
        }
    }

    private void setup_popover () {
        var pop = new Gtk.Popover ();
        button.set_popover (pop);
        popover = pop;
        button.notify["active"].connect (on_popover_active);
    }

    private void on_popover_active () {
        if (!button.active || popover == null)
            return;

        var navigator = new BreadcrumbFileNavigator (this.source_view.session, this.file);

        popover.set_child (navigator);
        navigator.search_entry.set_key_capture_widget (popover);

        navigator.close_requested.connect (() => {
            button.active = false;
            source_view.grab_focus ();
        });
    }

    private void setup_file_outline_popover () {
        var pop = new Gtk.Popover ();
        button.set_popover (pop);
        popover = pop;
        button.notify["active"].connect (on_outline_active);
    }

    private void on_outline_active () {
        if (!button.active || popover == null)
            return;

        var navigator = new BreadcrumbSymbolOutlineNavigator (source_view);

        popover.set_child (navigator);
        navigator.search_entry.set_key_capture_widget (popover);
        navigator.close_requested.connect (() => {
            button.active = false;
            source_view.grab_focus ();
        });
    }
}

public class Iide.BreadcrumbSymbolSegment : Gtk.Box {
    private SourceView source_view;
    private Gtk.MenuButton button;
    private SourceNodeItem current_item;

    // см. комментарий к BreadcrumbFileSegment.popover
    private unowned Gtk.Popover? popover = null;

    public BreadcrumbSymbolSegment (SourceView source_view, SourceNodeItem item) {
        Object (orientation: Gtk.Orientation.HORIZONTAL, spacing: 0);
        this.source_view = source_view;
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

        this.append (button);
        setup_popover ();
    }

    private void setup_popover () {
        var pop = new Gtk.Popover ();
        button.set_popover (pop);
        popover = pop;
        button.notify["active"].connect (on_popover_active);
    }

    private void on_popover_active () {
        if (!button.active)
            return;

        if (this.current_item.siblings.size < 2) {
            button.active = false;
            this.source_view.goto ((int) this.current_item.start_point.row,
                                   (int) this.current_item.start_point.column);
            return;
        }

        if (popover == null)
            return;

        var navigator = new BreadcrumbTreeSitterNavigator (source_view, this.current_item.siblings);
        popover.set_child (navigator);

        navigator.search_entry.set_key_capture_widget (popover);
        navigator.close_requested.connect (() => {
            button.active = false;
            source_view.grab_focus ();
        });
    }
}

public class Iide.BreadcrumbsBar : Gtk.Box {
    private Gtk.Box path_box; // Относительный путь: Проект > src > main.vala
    private Gtk.Box scope_box; // LSP-структура: MyClass > my_method
    private SourceView source_view;

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

    public void update_breadcrumbs (Gee.List<SourceNodeItem?> crumbs) {
        // Очистка контейнера
        var child = scope_box.get_first_child ();
        while (child != null) {
            var next = child.get_next_sibling ();
            scope_box.remove (child);
            child = next;
        }

        foreach (var crumb in crumbs) {
            var ts_segment = new BreadcrumbSymbolSegment (source_view, crumb);
            scope_box.append (ts_segment);
        }
    }
}