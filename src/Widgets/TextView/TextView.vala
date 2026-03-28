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

        if (settings.editor_font_size > 0) {
            font_zoomer.set_font_size ((double) settings.editor_font_size);
        }

        var action_group = new SimpleActionGroup ();

        var toggle_minimap_action = new SimpleAction.stateful ("toggle_minimap", null, new Variant.boolean (settings.show_minimap));
        toggle_minimap_action.activate.connect (() => {
            var state = !toggle_minimap_action.get_state ().get_boolean ();
            toggle_minimap_action.set_state (new Variant.boolean (state));
            settings.show_minimap = state;
            toggle_minimap_visible (state);
        });
        action_group.add_action (toggle_minimap_action);

        var zoom_in_action = new SimpleAction ("zoom_in_action", null);
        zoom_in_action.activate.connect (() => {
            font_zoomer.zoom_in ();
        });
        action_group.add_action (zoom_in_action);

        var zoom_out_action = new SimpleAction ("zoom_out_action", null);
        zoom_out_action.activate.connect (() => {
            font_zoomer.zoom_out ();
        });
        action_group.add_action (zoom_out_action);

        var zoom_reset_action = new SimpleAction ("zoom_reset_action", null);
        zoom_reset_action.activate.connect (() => {
            font_zoomer.zoom_reset ();
            settings.editor_font_size = 0;
        });
        action_group.add_action (zoom_reset_action);

        view.insert_action_group ("widget", action_group);

        var font_size_menu = new GLib.Menu ();
        font_size_menu.append ("Increase Font Size", "widget.zoom_in_action");
        font_size_menu.append ("Decrease Font Size", "widget.zoom_out_action");
        font_size_menu.append ("Reset Font Size to default", "widget.zoom_reset_action");

        var view_extra_menu = new GLib.Menu ();
        view_extra_menu.append("Show Minimap", "widget.toggle_minimap");
        view_extra_menu.append_submenu ("Font Size", font_size_menu);

        view.extra_menu = view_extra_menu;

        // #######################################
        // ## ShortcutController
        var trigger_in = Gtk.ShortcutTrigger.parse_string ("<Primary>plus");
        var action_in = new Gtk.NamedAction ("widget.zoom_in_action"); // Ссылаемся на имя в группе
        var shortcut_in = new Gtk.Shortcut (trigger_in, action_in);

        var trigger_out = Gtk.ShortcutTrigger.parse_string ("<Primary>minus");
        var action_out = new Gtk.NamedAction ("widget.zoom_out_action"); // Ссылаемся на имя в группе
        var shortcut_out = new Gtk.Shortcut (trigger_out, action_out);

        var trigger_reset = Gtk.ShortcutTrigger.parse_string ("<Primary>0");
        var action_reset = new Gtk.NamedAction ("widget.zoom_reset_action"); // Ссылаемся на имя в группе
        var shortcut_reset = new Gtk.Shortcut (trigger_reset, action_reset);

        var controller = new Gtk.ShortcutController ();
        controller.add_shortcut (shortcut_in);
        controller.add_shortcut (shortcut_out);
        controller.add_shortcut (shortcut_reset);
        view.add_controller (controller); // Добавляем контроллер к виджету

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
