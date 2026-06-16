/*
*/

public class Iide.LspDiagnosticsMark : GtkSource.Mark {
    public int severity { get; construct set; }
    public string diagnostic_message { get; construct set; }
    public string server_name { get; construct set; }
    public Json.Object? raw_json { get; construct set; default = null; }

    public LspDiagnosticsMark(string server_name, string lsp_category, int lsp_severity, string lsp_message, Json.Object? raw = null) {
        Object(
            name: null,
            category: lsp_category,
            severity: lsp_severity,
            diagnostic_message: lsp_message,
            server_name: server_name,
            raw_json: raw
        );
    }

    private static string category_from_severity(int severity) {
        switch (severity) {
        case 1:
            return "lsp_error";
        case 2:
            return "lsp_warning";
        case 3:
        case 4:
            return "lsp_info";
        }
        return "lsp_error";
    }

    public LspDiagnosticsMark.from_lsp_diagnostic(LspDiagnostic diagnostics, Json.Object? raw = null) {
        Object(
            name: null,
            category: category_from_severity(diagnostics.severity),
            severity: diagnostics.severity,
            diagnostic_message: diagnostics.message,
            server_name: diagnostics.server_name,
            raw_json: raw
        );
    }

    public static void set_mark_attributes(GtkSource.View text_view) {
        var error_mark_attrs = new GtkSource.MarkAttributes();
        var err_bg = Gdk.RGBA();
        err_bg.parse("#e01b2430");
        error_mark_attrs.set_background(err_bg);
        text_view.set_mark_attributes("lsp_error", error_mark_attrs, 100);

        var warning_mark_attrs = new GtkSource.MarkAttributes();
        var warn_bg = Gdk.RGBA();
        warn_bg.parse("#f5c21130");
        warning_mark_attrs.set_background(warn_bg);
        text_view.set_mark_attributes("lsp_warning", warning_mark_attrs, 90);

        var info_mark_attrs = new GtkSource.MarkAttributes();
        text_view.set_mark_attributes("lsp_info", info_mark_attrs, 80);
    }

    public static void clear_mark_attributes(string server_name, SourceView source_view) {
        if (source_view.lsp_marks.has_key (server_name)) {
            var marks_to_remove = source_view.lsp_marks.get (server_name);
            var buffer = (GtkSource.Buffer) source_view.buffer;
            foreach (var mark_to_remove in marks_to_remove) {
                buffer.delete_mark(mark_to_remove);
            }
            source_view.lsp_marks.unset (server_name);
        }
    }

    public string ? get_icon_name() {
        switch (severity) {
        case 1:
            return "dialog-error";
        case 2:
            return "dialog-warning";
        case 3:
        case 4:
            return "dialog-information";
        }
        return null;
    }
}
