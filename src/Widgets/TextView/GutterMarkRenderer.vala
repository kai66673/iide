using Gtk;
using GtkSource;
using GLib;

public class Iide.GutterMarkRenderer : GutterRenderer {
    private int current_icon_size = 16;

    private Gtk.IconPaintable error_paintable;
    private Gtk.IconPaintable warning_paintable;
    private Gdk.RGBA[] error_colors = {
        Gdk.RGBA() {red = 1.0f, green = 0.0f, blue = 0.0f, alpha = 0.86f}
    };
    private Gdk.RGBA[] warning_colors = {
        Gdk.RGBA() {red = 0.7f, green = 0.7f, blue = 0.0f, alpha = 0.86f}
    };

    public GutterMarkRenderer() {
        Object();
        init_paintable_icons ();
    }

    private void init_paintable_icons() {
        var icon_provider = SymbIconProvider.get_instance ();
        var display = Gdk.Display.get_default ();
        var theme = Gtk.IconTheme.get_for_display (display);

        var error_icon_name = icon_provider.icon_name (IconID.COD_ERROR);
        var error_gicon = new GLib.ThemedIcon (error_icon_name);
        error_paintable = theme.lookup_by_gicon (error_gicon, current_icon_size, 1, Gtk.TextDirection.NONE, 0);

        var warning_icon_name = icon_provider.icon_name (IconID.COD_WARNING);
        var warning_gicon = new GLib.ThemedIcon (warning_icon_name);
        warning_paintable = theme.lookup_by_gicon (warning_gicon, current_icon_size, 1, Gtk.TextDirection.NONE, 0);
    }

    public void set_icons_size (int size) {
        if (current_icon_size == size) {
            return;
        }
        current_icon_size = size;
        queue_resize ();

        var gutter = (Gutter) get_parent ();
        if (gutter != null) {
            gutter.queue_allocate ();
        }
    }

    public override void measure (Gtk.Orientation orientation, int for_size, out int minimum, out int natural, out int minimum_baseline, out int natural_baseline) {
        minimum_baseline = natural_baseline = -1;
        if (orientation == Gtk.Orientation.HORIZONTAL) {
            minimum = natural = current_icon_size;
        } else {
            minimum = natural = 0;
        }
    }

    public override void snapshot_line (Gtk.Snapshot snapshot, GutterLines lines, uint line) {
        var buffer = get_buffer ();
        if (buffer == null) {
            return;
        }

        Gtk.TextIter iter;
        lines.get_iter_at_line (out iter, line);
        var marks = iter.get_marks ();

        bool has_error = false;
        bool has_warning = false;
        foreach (var text_mark in marks) {
            var lsp_mark = text_mark as LspDiagnosticsMark;
            if (lsp_mark != null) {
                if (lsp_mark.severity == 1) {
                    has_error = true;
                } else {
                    has_warning = true;
                }
            }
        }

        if (!has_error && !has_warning) {
            return;
        }

        int y, height;
        lines.get_line_yrange (line, GutterRendererAlignmentMode.CELL, out y, out height);

        var snapshot_size = (float) current_icon_size;
        var x = (float) xpad;
        var y_pos = (float) y + ((float) height - snapshot_size) / 2.0f;

        var point = Graphene.Point () { x = x, y = y_pos };
        snapshot.translate (point);
        if (has_warning)
            warning_paintable.snapshot_symbolic (snapshot, snapshot_size, snapshot_size, warning_colors);
        if (has_error)
            error_paintable.snapshot_symbolic (snapshot, snapshot_size, snapshot_size, error_colors);
        snapshot.translate (Graphene.Point () { x = -x, y = -y_pos });
    }
}
