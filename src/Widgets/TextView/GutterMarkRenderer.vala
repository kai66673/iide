using Gtk;
using GtkSource;
using GLib;

public class Iide.GutterMarkRenderer : GutterRenderer {
    private int current_icon_size = 16;

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

        string? icon_name_to_draw = null;

        foreach (var text_mark in marks) {
            var lsp_mark = text_mark as LspDiagnosticsMark;
            if (lsp_mark != null) {
                icon_name_to_draw = lsp_mark.get_icon_name ();
            }
        }

        if (icon_name_to_draw == null) {
            return;
        }

        var display = Gdk.Display.get_default ();
        if (display == null) {
            return;
        }

        var theme = Gtk.IconTheme.get_for_display (display);
        try {
            var gicon = new GLib.ThemedIcon (icon_name_to_draw);
            var paintable = theme.lookup_by_gicon (gicon, current_icon_size, 1, Gtk.TextDirection.NONE, 0);
            if (paintable == null) {
                return;
            }

            int y, height;
            lines.get_line_yrange (line, GutterRendererAlignmentMode.CELL, out y, out height);

            var snapshot_size = (float) current_icon_size;
            var x = (float) xpad;
            var y_pos = (float) y + ((float) height - snapshot_size) / 2.0f;

            var point = Graphene.Point () { x = x, y = y_pos };
            snapshot.translate (point);
            paintable.snapshot (snapshot, snapshot_size, snapshot_size);
            snapshot.translate (Graphene.Point () { x = -x, y = -y_pos });
        } catch (Error e) {
        }
    }
}
