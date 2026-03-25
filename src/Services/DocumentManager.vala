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
    public Gee.HashMap<string, TextView> documents;

    public DocumentManager () {
        documents = new Gee.HashMap<string, TextView> ();
    }

    public signal void document_opened (TextView document);
    public signal void document_closed (string uri);

    public Panel.Widget? open_document (GLib.File file, Gtk.Window window) {
        string uri = file.get_uri ();
        if (documents.has_key (uri)) {
            var widget = documents.get (uri);
            widget.raise ();
            widget.view_grab_focus ();
            return widget;
        } else {
            var buffer = new GtkSource.Buffer (null);
            var source_file = new GtkSource.File ();
            source_file.location = file;
            var file_loader = new GtkSource.FileLoader (buffer, source_file);
            Iide.TextView? panel_widget = null;
            file_loader.load_async.begin (Priority.DEFAULT, null, null, (obj, res) => {
                try {
                    file_loader.load_async.end (res);
                    panel_widget = new Iide.TextView (file, buffer);
                    panel_widget.notify["parent"].connect (() => {
                        if (panel_widget.parent == null) {
                            close_document (file);
                        }
                    });
                    documents.set (uri, panel_widget);
                    document_opened (panel_widget);
                } catch (Error e) {
                    var dialog = new Adw.AlertDialog ("Error Opening File", "Failed to read file %s: %s".printf (file.get_path (), e.message));
                    dialog.add_response ("ok", "OK");
                    dialog.present (window);
                }
            });
            return panel_widget;
        }
    }



    public bool close_document (GLib.File file) {
        string uri = file.get_uri ();
        if (documents.has_key (uri)) {
            documents.unset (uri);
            document_closed (uri);
            return true;
        }
        return false;
    }

    public Panel.Widget? get_document_for_file (GLib.File file) {
        string uri = file.get_uri ();
        return documents.get (uri);
    }

    public bool is_file_open (GLib.File file) {
        return documents.has_key (file.get_uri ());
    }
}
