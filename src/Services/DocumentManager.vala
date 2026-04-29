/*
 * documentmanager.vala
 *
 * Copyright 2026 kai
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

using Gee;
using GLib;
using Gtk;
using Panel;

public class Iide.DocumentManager : GLib.Object {
    public Window window;
    private IdeLspService lsp_service;

    private string? current_workspace_root;

    private LoggerService logger = LoggerService.get_instance ();
    private static DocumentManager? _instance;

    public static DocumentManager get_instance () {
        return _instance;
    }

    public Gee.HashMap<string, TextView> _documents;
    public Gee.HashMap<string, TextView> documents {
        get {
            _documents = new Gee.HashMap<string, TextView> ();
            window.grid.foreach_frame ((frame) => {
                var pages = frame.get_pages ();

                for (uint i = 0; i < pages.get_n_items (); i++) {
                    var item = pages.get_item (i) as Adw.TabPage;
                    if (item == null) {
                        continue;
                    }
                    var child = item.get_child ();
                    if (child == null) {
                        continue;
                    }
                    var text_view = child as TextView;
                    if (text_view != null) {
                        _documents.set (text_view.uri, text_view);
                    }
                }
            });
            return _documents;
        }
    }

    public DocumentManager (Window window) {
        this.window = window;
        DocumentManager._instance = this;
        // documents = new Gee.HashMap<string, TextView> ();
        lsp_service = IdeLspService.get_instance ();

        lsp_service.diagnostics_updated.connect ((uri, diagnostics) => {
            var doc = documents.get (uri);
            if (doc != null) {
                var lsp_diagnostics = new Gee.ArrayList<IdeLspDiagnostic> ();
                foreach (var diag in diagnostics) {
                    var d = new IdeLspDiagnostic ();
                    d.severity = diag.severity;
                    d.message = diag.message;
                    d.start_line = diag.start_line;
                    d.start_column = diag.start_column;
                    d.end_line = diag.end_line;
                    d.end_column = diag.end_column;
                    lsp_diagnostics.add (d);
                }

                Idle.add (() => {
                    doc.update_diagnostics (lsp_diagnostics);
                    return false;
                });
            }
        });
    }

    public void set_workspace_root (string? root) {
        current_workspace_root = root;
    }

    public signal void document_opened (TextView document);

    public Panel.Widget? open_document (GLib.File file, Panel.Position ? pos) {
        return open_document_with_selection (file, -1, -1, -1, pos);
    }

    public Panel.Widget? open_document_with_selection (GLib.File file, int line, int start_col, int end_col, Panel.Position ? pos) {
        string uri = file.get_uri ();

        var docs = documents;
        if (docs.has_key (uri)) {
            var widget = docs.get (uri);
            widget.raise ();
            widget.view_grab_focus ();
            if (line >= 0) {
                widget.select_and_scroll (line, start_col, end_col, false);
            }
            return widget;
        } else {
            var shared_table = Iide.StyleService.get_instance ().shared_table;
            var buffer = new GtkSource.Buffer (shared_table);
            var source_file = new GtkSource.File ();
            source_file.location = file;
            var file_loader = new GtkSource.FileLoader (buffer, source_file);
            Iide.TextView? panel_widget = null;
            file_loader.load_async.begin (Priority.DEFAULT, null, null, (obj, res) => {
                try {
                    file_loader.load_async.end (res);
                    panel_widget = new Iide.TextView (file, buffer, window);

                    panel_widget.buffer_saved.connect (() => {
                        string content = ((GtkSource.Buffer) panel_widget.text_view.buffer).text;
                        lsp_service.change_document.begin (uri, content);
                    });

                    if (pos == null) {
                        window.grid.add (panel_widget);
                    } else {
                        window.add_widget (panel_widget, pos);
                    }
                    panel_widget.raise ();
                    panel_widget.view_grab_focus ();
                    logger.debug ("Doc", "Document panel widget created: " + uri);

                    if (line >= 0) {
                        // TODO: with timeout...
                        panel_widget.select_and_scroll (line, start_col, end_col, true);
                    }

                    string content = buffer.text;
                    string? lang_id = lsp_service.get_language_id_for_file (file);
                    if (lang_id != null) {
                        lsp_service.open_document.begin (uri, lang_id, content, current_workspace_root, panel_widget.text_view);
                    }
                } catch (Error e) {
                    logger.error ("Doc", "Error Opening File", "Failed to read file %s: %s".printf (file.get_path (), e.message));
                }
            });
            return panel_widget;
        }
    }

    public Panel.Widget? get_document_for_file (GLib.File file) {
        string uri = file.get_uri ();
        return documents.get (uri);
    }

    public bool is_file_open (GLib.File file) {
        return documents.has_key (file.get_uri ());
    }

    public Gee.ArrayList<string> get_open_document_uris () {
        var uris = new Gee.ArrayList<string> ();
        foreach (var uri in documents.keys) {
            uris.add (uri);
        }
        return uris;
    }

    public void open_document_by_uri (string uri) {
        var file = GLib.File.new_for_uri (uri);
        if (file.query_exists (null)) {
            open_document (file, null);
        }
    }

    public bool navigate_to (NavigationPoint nav_point) {
        var docs = documents;
        var uri = nav_point.file.get_uri ();
        if (docs.has_key (uri)) {
            var widget = docs.get (uri);
            widget.raise ();
            widget.view_grab_focus ();
            widget.select_and_scroll (nav_point.line, nav_point.column, nav_point.column, false);
            return true;
        }
        return false;
    }
}