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
    private GtkSource.Map source_map;
    private Iide.TreeSitterManager ts_manager;
    private BaseTreeSitterHighlighter? ts_highlighter;
    private FontZoomer font_zoomer;
    private Iide.SettingsService settings;

    public GtkSource.LanguageManager manager;
    public string uri { get; private set; }

    public bool is_modified { get { return ((GtkSource.Buffer) view.buffer).get_modified (); } }

    public TextView (GLib.File file, GtkSource.Buffer buffer) {
        Object ();
        this.uri = file.get_uri ();
        this.ts_manager = new TreeSitterManager ();
        this.ts_highlighter = null;
        this.settings = Iide.SettingsService.get_instance ();

        manager = GtkSource.LanguageManager.get_default ();
        var adw_style_manager = Adw.StyleManager.get_default ();

        var style_manager = GtkSource.StyleSchemeManager.get_default ();
        if (adw_style_manager.color_scheme == Adw.ColorScheme.FORCE_LIGHT) {
            buffer.set_style_scheme (style_manager.get_scheme ("Adwaita"));
        } else {
            buffer.set_style_scheme (style_manager.get_scheme ("Adwaita-dark"));
        }

        adw_style_manager.notify["color-scheme"].connect (() => {
            if (adw_style_manager.color_scheme == Adw.ColorScheme.FORCE_LIGHT) {
                buffer.set_style_scheme (style_manager.get_scheme ("Adwaita"));
            } else {
                buffer.set_style_scheme (style_manager.get_scheme ("Adwaita-dark"));
            }
        });

        view = new GtkSource.View.with_buffer (buffer);
        font_zoomer = new FontZoomer (view);

        // Connect to application-level zoom and minimap changes
        var app = GLib.Application.get_default () as Iide.Application;
        if (app != null) {
            app.zoom_changed.connect ((level) => {
                font_zoomer.set_zoom_level (level);
            });
            app.minimap_changed.connect ((visible) => {
                toggle_minimap_visible (visible);
            });
        }

        // Build extra menu for context menu
        var zoom_section = new GLib.Menu ();
        zoom_section.append (_("Zoom In"), "app.zoom_in");
        zoom_section.append (_("Zoom Out"), "app.zoom_out");
        zoom_section.append (_("Reset Zoom"), "app.zoom_reset");

        var view_section = new GLib.Menu ();
        view_section.append (_("Minimap"), "app.toggle_minimap");

        var extra_menu = new GLib.Menu ();
        extra_menu.append_section (null, zoom_section);
        extra_menu.append_section (null, view_section);
        view.extra_menu = extra_menu;

        // Connect to settings changes to apply to all open documents
        settings.editor_setting_changed.connect ((key) => {
            switch (key) {
                case "editor-font-size":
                    font_zoomer.set_zoom_level (settings.editor_font_size);
                    break;
                case "show-minimap":
                    toggle_minimap_visible (settings.show_minimap);
                    break;
                case "show-line-numbers":
                    view.show_line_numbers = settings.show_line_numbers;
                    break;
                case "highlight-current-line":
                    view.highlight_current_line = settings.highlight_current_line;
                    break;
                case "auto-indent":
                    view.auto_indent = settings.auto_indent;
                    break;
            }
        });

        // #######################################
        // ## SpaceDrawer
        var space_drawer = view.get_space_drawer ();

        // 2. Устанавливаем типы отображаемых символов
        space_drawer.set_enable_matrix (true);
        space_drawer.set_types_for_locations (
                                              GtkSource.SpaceLocationFlags.ALL,
                                              GtkSource.SpaceTypeFlags.NONE
        );
        space_drawer.set_types_for_locations (
                                              GtkSource.SpaceLocationFlags.LEADING | GtkSource.SpaceLocationFlags.TRAILING,
                                              GtkSource.SpaceTypeFlags.SPACE | GtkSource.SpaceTypeFlags.TAB
        );


        buffer.set_modified (false);

        icon_name = "text-x-generic";

        change_syntax_highlight_from_file (file);

        ts_highlighter = ts_manager.get_ts_highlighter (view);

        view.show_line_numbers = settings.show_line_numbers;
        view.highlight_current_line = settings.highlight_current_line;
        view.auto_indent = settings.auto_indent;
        view.indent_on_tab = true;

        source_map = new GtkSource.Map ();
        source_map.set_view (view);
        source_map.add_css_class ("textview-map");
        source_map.visible = settings.show_minimap;

        var scroll = new Gtk.ScrolledWindow ();
        scroll.hexpand = true;
        scroll.vexpand = true;

        scroll.set_child (view);

        scroll.get_vadjustment ().bind_property ("value",
                                                 source_map.get_vadjustment (), "value",
                                                 BindingFlags.BIDIRECTIONAL | BindingFlags.SYNC_CREATE);

        var subbox = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
        subbox.homogeneous = false;
        subbox.append (scroll);
        subbox.append (source_map);

        var font_map = Pango.CairoFontMap.get_default ();
        source_map.set_font_map (font_map);

        var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
        box.append (subbox);
        child = box;

        title = file.get_basename ();

        save_delegate = new Iide.SaveDelegate (this);
        modified = false;

        buffer.modified_changed.connect_after (() => {
            modified = view.buffer.get_modified ();
        });
    }

    public void toggle_minimap_visible(bool visible) {
        source_map.visible = visible;
    }

    public void view_grab_focus () {
        view.grab_focus ();
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
