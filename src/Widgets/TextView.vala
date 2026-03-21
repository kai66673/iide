/*
 * textdocument.vala
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



public class Iide.SaveDelegate : Panel.SaveDelegate {
    private Iide.TextView view;
    public SaveDelegate (Iide.TextView view) {
        Object ();
        this.view = view;

        var file = GLib.File.new_for_uri (view.uri);
        title = view.title;
        subtitle = file.get_path ();
    }

    public override bool save (GLib.Task task) {
        message ("Saving in delegate...");
        var result = view.save ();
        task.return_boolean (result);
        return result;
    }

    public override void close () {
        view.force_close ();
    }

    public override void discard () {
        view.force_close ();
    }
}

public class Iide.TextView : Panel.Widget {
    private GtkSource.View view;
    private Iide.TreeSitterManager ts_manager;
    private unowned TreeSitter.Language? ts_language;
    private TreeSitterHighlighter? ts_highlighter;

    public GtkSource.LanguageManager manager;
    public string uri { get; private set; }

    public bool is_modified { get { return ((GtkSource.Buffer) view.buffer).get_modified (); } }

    public TextView (GLib.File file, GtkSource.Buffer buffer) {
        Object ();
        this.uri = file.get_uri ();
        this.ts_manager = new TreeSitterManager ();
        this.ts_language = null;
        this.ts_highlighter = null;

        manager = GtkSource.LanguageManager.get_default ();
        var adw_style_manager = Adw.StyleManager.get_default ();

        var style_manager = GtkSource.StyleSchemeManager.get_default ();
        if (adw_style_manager.color_scheme == Adw.ColorScheme.FORCE_LIGHT) {
            buffer.set_style_scheme (style_manager.get_scheme ("Adwaita"));
        } else {
            buffer.set_style_scheme (style_manager.get_scheme ("Adwaita-dark"));
        }

        // Handle file selection to open documents
        adw_style_manager.notify["color-scheme"].connect (() => {
            if (adw_style_manager.color_scheme == Adw.ColorScheme.FORCE_LIGHT) {
                buffer.set_style_scheme (style_manager.get_scheme ("Adwaita"));
            } else {
                buffer.set_style_scheme (style_manager.get_scheme ("Adwaita-dark"));
            }
        });

        view = new GtkSource.View.with_buffer (buffer);

        buffer.set_modified (false);

        icon_name = "text-x-generic";

        change_syntax_highlight_from_file (file);

        this.ts_language = ts_manager.get_ts_language (buffer);
        var ts_query = ts_manager.get_ts_query (buffer);

        if (this.ts_language != null && ts_query != null) {
            var parser = new TreeSitter.Parser ();
            parser.set_language (this.ts_language);
            var ts_tree = parser.parse_string (null, buffer.text.data);
            if (ts_tree == null) {
                message ("Errors parsing file %s", file.get_uri ());
            } else {
                buffer.highlight_syntax = false;
                this.ts_highlighter = new TreeSitterHighlighter (view, this.ts_language, ts_query);
            }
        }

        view.show_line_numbers = true;
        view.highlight_current_line = true;
        view.auto_indent = true;
        view.indent_on_tab = true;

        var scroll = new Gtk.ScrolledWindow ();
        scroll.vexpand = true;
        scroll.set_child (view);

        var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
        box.append (scroll);
        child = box;

        title = file.get_basename ();

        save_delegate = new Iide.SaveDelegate (this);
        modified = false;

        buffer.modified_changed.connect_after (() => {
            modified = view.buffer.get_modified ();
        });
    }

    // lang can be null, in the case of *No highlight style* aka Normal text
    public GtkSource.Language? language {
        set {
            ((GtkSource.Buffer) view.buffer).language = value;
        }
        get {
            return ((GtkSource.Buffer) view.buffer).language;
        }
    }

    public bool save () {
        try {
            var text = view.buffer.text;
            var file = GLib.File.new_for_uri (uri);
            file.replace_contents (text.data, null, false, GLib.FileCreateFlags.NONE, null);
            ((GtkSource.Buffer) view.buffer).set_modified (false);
        } catch (Error e) {
            critical (e.message);
        }
        return true;
    }

    public void change_syntax_highlight_from_file (GLib.File file) {
        string mime_type = mime_type_for_file (file);
        message ("MIME: _ " + mime_type);

        icon_name = IconProvider.get_mime_type_icon_name (mime_type);
        language = manager.guess_language (file.get_path (), mime_type);

        // Fake file type detection
        // "Not all files are equal"
        if (file.get_basename () == "CMakeLists.txt") {
            language = manager.get_language ("cmake");
            icon_name = "text-x-cmake"; // Specific icon for CMake
        }
    }
}
