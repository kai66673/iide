public class Iide.EditorStatusBar : Gtk.Box {
    private SourceView source_view;
    private Gtk.Label pos_label;
    private Gtk.Label mode_label;

    private DiagnosticsBar diagnostic_bar;
    private BreadcrumbsBar breadcrumps_bar;

    public EditorStatusBar (SourceView source_view) {
        Object (orientation: Gtk.Orientation.HORIZONTAL, spacing: 12);
        this.source_view = source_view;
        this.add_css_class ("editor-status-bar");

        // Левая часть: Breadcrumbs
        breadcrumps_bar = new BreadcrumbsBar (source_view);
        this.append (breadcrumps_bar);
        breadcrumps_bar.update_file_path (GLib.File.new_for_uri (source_view.uri),
                                          GLib.File.new_for_path (ProjectManager.get_instance ().get_workspace_root_path ()));

        // spacer
        var spacer_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 2);
        spacer_box.hexpand = true;
        this.append (spacer_box);

        // Правая часть: Статистика
        var info_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);

        mode_label = new Gtk.Label ("INS");
        mode_label.add_css_class ("dim-label");
        mode_label.height_request = 24;

        pos_label = new Gtk.Label ("1:1");

        info_box.append (mode_label);
        info_box.append (pos_label);
        this.append (info_box);

        diagnostic_bar = new DiagnosticsBar (source_view);

        // Добавляем в инфо-бокс перед позицией курсора
        info_box.prepend (diagnostic_bar);
    }

    public void update_diagnostics (int errors, int warnings) {
        this.diagnostic_bar.update_diagnostics (errors, warnings);
    }

    public void update_breadcrumbs (Gee.List<SourceNodeItem?> crumbs) {
        breadcrumps_bar.update_breadcrumbs (crumbs);
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