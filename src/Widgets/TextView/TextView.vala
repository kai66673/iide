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
    private GtkSource.View _text_view;
    private GtkSource.Map source_map;
    private Iide.TreeSitterManager ts_manager;
    private BaseTreeSitterHighlighter? ts_highlighter;
    private FontZoomer font_zoomer;
    private Iide.SettingsService settings;
    private GtkSource.MarkAttributes error_mark_attrs;
    private GtkSource.MarkAttributes warning_mark_attrs;
    private GtkSource.MarkAttributes info_mark_attrs;

    public GtkSource.LanguageManager manager;
    public string uri { get; private set; }
    public GtkSource.View text_view { get { return _text_view; } }

    public bool is_modified { get { return ((GtkSource.Buffer) _text_view.buffer).get_modified (); } }

    public signal void text_changed (string text);
    public signal void buffer_saved ();

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

        _text_view = new GtkSource.View.with_buffer (buffer);
        font_zoomer = new FontZoomer (_text_view);

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
        _text_view.extra_menu = extra_menu;

        // Connect to settings changes to apply to all open documents
        settings.editor_setting_changed.connect ((key) => {
            switch (key) {
                case "editor-font-size" :
                    font_zoomer.set_zoom_level (settings.editor_font_size);
                    break;
                case "show-minimap":
                    toggle_minimap_visible (settings.show_minimap);
                    break;
                case "show-line-numbers":
                    _text_view.show_line_numbers = settings.show_line_numbers;
                    break;
                case "highlight-current-line":
                    _text_view.highlight_current_line = settings.highlight_current_line;
                    break;
                case "auto-indent":
                    _text_view.auto_indent = settings.auto_indent;
                    break;
            }
        });

        // #######################################
        // ## SpaceDrawer
        var space_drawer = _text_view.get_space_drawer ();

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

        ts_highlighter = ts_manager.get_ts_highlighter (_text_view);

        _text_view.show_line_numbers = settings.show_line_numbers;
        _text_view.highlight_current_line = settings.highlight_current_line;
        _text_view.auto_indent = settings.auto_indent;
        _text_view.indent_on_tab = true;

        source_map = new GtkSource.Map ();
        source_map.set_view (_text_view);
        source_map.add_css_class ("textview-map");
        source_map.visible = settings.show_minimap;

        _text_view.show_line_numbers = true;
        _text_view.set_show_line_marks (true);

        var left_gutter = _text_view.get_gutter (Gtk.TextWindowType.LEFT);
        left_gutter.visible = true;

        var text_buffer = (Gtk.TextBuffer) _text_view.buffer;
        var error_tag = new Gtk.TextTag ("lsp_error_line");
        var error_bg = Gdk.RGBA ();
        error_bg.parse ("#e01b24");
        error_bg.alpha = 0.15f;
        error_tag.background_rgba = error_bg;
        text_buffer.tag_table.add (error_tag);

        var warning_tag = new Gtk.TextTag ("lsp_warning_line");
        var warning_bg = Gdk.RGBA ();
        warning_bg.parse ("#f5c211");
        warning_bg.alpha = 0.15f;
        warning_tag.background_rgba = warning_bg;
        text_buffer.tag_table.add (warning_tag);

        error_mark_attrs = new GtkSource.MarkAttributes ();
        error_mark_attrs.set_icon_name ("dialog-error");
        var err_bg = Gdk.RGBA ();
        err_bg.parse ("#e01b24");
        error_mark_attrs.set_background (err_bg);
        _text_view.set_mark_attributes ("error", error_mark_attrs, 100);

        warning_mark_attrs = new GtkSource.MarkAttributes ();
        warning_mark_attrs.set_icon_name ("dialog-warning");
        var warn_bg = Gdk.RGBA ();
        warn_bg.parse ("#f5c211");
        warning_mark_attrs.set_background (warn_bg);
        _text_view.set_mark_attributes ("warning", warning_mark_attrs, 90);

        info_mark_attrs = new GtkSource.MarkAttributes ();
        info_mark_attrs.set_icon_name ("dialog-information");
        _text_view.set_mark_attributes ("info", info_mark_attrs, 80);

        var scroll = new Gtk.ScrolledWindow ();
        scroll.hexpand = true;
        scroll.vexpand = true;

        scroll.set_child (_text_view);

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
            modified = _text_view.buffer.get_modified ();
        });

        buffer.changed.connect (() => {
            text_changed (buffer.text);
        });
    }

    public override void size_allocate (int width, int height, int baseline) {
        base.size_allocate (width, height, baseline);
        source_map.visible = settings.show_minimap && width >= 600;
    }

    public void toggle_minimap_visible (bool visible) {
        source_map.visible = visible;
    }

    public void view_grab_focus () {
        _text_view.grab_focus ();
    }

    // lang can be null, in the case of *No highlight style* aka Normal text
    public GtkSource.Language? language {
        set {
            ((GtkSource.Buffer) _text_view.buffer).language = value;
        }
        get {
            return ((GtkSource.Buffer) _text_view.buffer).language;
        }
    }

    public bool save () {
        try {
            var text = _text_view.buffer.text;
            var file = GLib.File.new_for_uri (uri);
            file.replace_contents (text.data, null, false, GLib.FileCreateFlags.NONE, null);
            ((GtkSource.Buffer) _text_view.buffer).set_modified (false);
            buffer_saved ();
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

    public void update_diagnostics (Gee.ArrayList<IdeLspDiagnostic> diagnostics) {
        var buffer = (GtkSource.Buffer) _text_view.buffer;
        var text_buffer = (Gtk.TextBuffer) buffer;

        text_buffer.begin_user_action ();

        Gtk.TextIter start, end;
        buffer.get_start_iter (out start);
        buffer.get_end_iter (out end);
        buffer.remove_source_marks (start, end, null);
        text_buffer.remove_tag_by_name ("lsp_error_line", start, end);
        text_buffer.remove_tag_by_name ("lsp_warning_line", start, end);

        int line_count = buffer.get_line_count ();

        foreach (var diag in diagnostics) {
            if (diag.start_line >= line_count) {
                continue;
            }

            Gtk.TextIter start_iter, line_end_iter, end_iter;
            text_buffer.get_iter_at_line (out start_iter, diag.start_line);
            text_buffer.get_iter_at_line (out line_end_iter, diag.start_line);
            line_end_iter.forward_line ();

            string category;
            switch (diag.severity) {
            case 1 :
                category = "error";
                text_buffer.apply_tag_by_name ("lsp_error_line", start_iter, line_end_iter);
                break;
            case 2:
                category = "warning";
                text_buffer.apply_tag_by_name ("lsp_warning_line", start_iter, line_end_iter);
                break;
            case 3:
            case 4:
                category = "info";
                break;
            default:
                category = "error";
                break;
            }

            buffer.create_source_mark (null, category, start_iter);
        }

        text_buffer.end_user_action ();
    }
}
