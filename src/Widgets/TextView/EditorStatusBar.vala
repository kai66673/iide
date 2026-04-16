public class Iide.EditorStatusBar : Gtk.Box {
    private Gtk.Box breadcrumbs_container;
    private Gtk.Label pos_label;
    private Gtk.Label mode_label;

    private Gtk.CssProvider provider = new Gtk.CssProvider ();

    public signal void breadcrumb_clicked (uint line, uint column);

    public EditorStatusBar () {
        Object (orientation: Gtk.Orientation.HORIZONTAL, spacing: 12);
        this.add_css_class ("editor-status-bar");

        // Левая часть: Breadcrumbs
        breadcrumbs_container = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
        breadcrumbs_container.set_hexpand (true);
        this.append (breadcrumbs_container);
        breadcrumbs_container.height_request = 24;

        // Правая часть: Статистика
        var info_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);

        mode_label = new Gtk.Label ("INS");
        mode_label.add_css_class ("dim-label");
        mode_label.height_request = 24;

        pos_label = new Gtk.Label ("1:1");

        info_box.append (mode_label);
        info_box.append (pos_label);
        this.append (info_box);

        provider.load_from_string ("button { max-height: 24px; min-height: 24px; padding: 0 2px 0 2px; font-size: 0.85em; }");
    }

    public void update_breadcrumbs (Gee.List<BreadcrumbItem?> crumbs) {
        // Очистка контейнера
        var child = breadcrumbs_container.get_first_child ();
        while (child != null) {
            var next = child.get_next_sibling ();
            breadcrumbs_container.remove (child);
            child = next;
        }

        foreach (var crumb in crumbs) {
            var btn = new Gtk.Button.with_label (crumb.name + " >");
            btn.add_css_class ("flat");
            btn.get_style_context ().add_provider (provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
            btn.vexpand = false;
            btn.valign = Gtk.Align.CENTER;
            breadcrumbs_container.append (btn);

            btn.clicked.connect (() => {
                // Генерируем сигнал или вызываем метод перемещения курсора
                this.breadcrumb_clicked (crumb.start_point.row, crumb.start_point.column);
            });
        }
    }

    public void update_position (int line, int col, int selection_len = 0) {
        if (selection_len > 0) {
            pos_label.label = "%d:%d (%d selected)".printf (line + 1, col + 1, selection_len);
        } else {
            pos_label.label = "%d:%d".printf (line + 1, col + 1);
        }
    }

    public void update_mode (bool overwrite) {
        mode_label.label = overwrite ? "OVR" : "INS";
    }
}
