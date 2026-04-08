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
    private GutterMarkRenderer mark_renderer;

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

        var completion = _text_view.get_completion ();
        // Настройки для борьбы с багами геометрии
        completion.show_icons = false; // Упрощаем попап, чтобы не ломать размеры
        completion.remember_info_visibility = false;
        var provider = new OldLspCompletionProvider (this);

        completion.add_provider (provider);

        // completion.hide.connect (() => {
        // print ("[TextView] Completion hidden\n");
        // });

        // completion.show.connect (() => {
        // print ("[TextView] Completion show requested\n");
        // });

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
        if (ts_highlighter != null) {
            ((GtkSource.Buffer) (_text_view.buffer)).highlight_syntax = false;
        }

        _text_view.show_line_numbers = settings.show_line_numbers;
        _text_view.highlight_current_line = settings.highlight_current_line;
        _text_view.auto_indent = settings.auto_indent;
        _text_view.indent_on_tab = true;

        source_map = new GtkSource.Map ();
        source_map.set_view (_text_view);
        source_map.add_css_class ("textview-map");
        source_map.visible = settings.show_minimap;

        _text_view.show_line_numbers = true;
        _text_view.set_show_line_marks (false);

        var left_gutter = _text_view.get_gutter (Gtk.TextWindowType.LEFT);
        left_gutter.visible = true;

        mark_renderer = new GutterMarkRenderer ();
        mark_renderer.set_icons_size (get_icon_size_for_zoom (font_zoomer.get_zoom_level ()));
        left_gutter.insert (mark_renderer, 0);

        LspDiagnosticsMark.set_mark_attributes (_text_view);

        font_zoomer.zoom_changed.connect ((level) => {
            mark_renderer.set_icons_size (get_icon_size_for_zoom (level));
        });

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

        _text_view.has_tooltip = true;
        _text_view.query_tooltip.connect (on_query_tooltip);
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
        var text_buffer = (Gtk.TextBuffer) _text_view.buffer;

        text_buffer.begin_user_action ();

        LspDiagnosticsMark.clear_mark_attributes (_text_view);

        int line_count = text_buffer.get_line_count ();

        foreach (var diag in diagnostics) {
            if (diag.start_line >= line_count) {
                continue;
            }

            Gtk.TextIter start_iter;
            text_buffer.get_iter_at_line (out start_iter, diag.start_line);

            var mark = new LspDiagnosticsMark.from_lsp_diagnostic (diag);
            text_buffer.add_mark (mark, start_iter); // Добавляем в буфер вручную
        }

        text_buffer.end_user_action ();
    }

    private int get_icon_size_for_zoom (int zoom_level) {
        return FontSizeHelper.get_size_for_zoom_level (zoom_level);
    }

    private bool on_query_tooltip (int x, int y, bool keyboard_mode, Gtk.Tooltip tooltip) {
        Gtk.TextIter iter;

        // Преобразуем координаты окна в координаты буфера
        int buffer_x, buffer_y;
        _text_view.window_to_buffer_coords (Gtk.TextWindowType.WIDGET, x, y, out buffer_x, out buffer_y);

        // Получаем итератор в месте курсора мыши
        if (!_text_view.get_iter_at_location (out iter, buffer_x, buffer_y)) {
            return false;
        }

        // Ищем маркеры в этой строке (по категории "error")
        var buffer = (GtkSource.Buffer) _text_view.buffer;
        var marks = buffer.get_source_marks_at_line (iter.get_line (), null);

        if (marks == null) {
            return false;
        }

        var sb = new StringBuilder ();

        string separator = "";
        for (int i = 0; i < 40; i++)separator += "─";

        foreach (var mark in marks) {
            var lsp_mark = mark as LspDiagnosticsMark;
            if (lsp_mark == null) {
                continue;
            }

            string icon;
            string header_color;

            switch (lsp_mark.severity) {
            case 1 :
                icon = "❌";
                header_color = "#F44336"; // Красный
                break;
            case 2:
                icon = "⚠️";
                header_color = "#FF9800"; // Оранжевый
                break;
            case 3:
            case 4:
                icon = "ℹ️";
                header_color = "#2196F3"; // Синий
                break;
            default:
                icon = "❌";
                header_color = "#F44336"; // Красный
                break;
            }

            if (sb.len > 0) {
                sb.append ("\n" + separator + "\n");
            }

            // Заголовок и основное сообщение
            sb.append_printf ("%s <span font_weight='bold' foreground='%s'>%s</span>\n",
                              icon, header_color, lsp_mark.category.up ());
            sb.append_printf ("<span>%s</span>", GLib.Markup.escape_text (lsp_mark.diagnostic_message));
        }

        if (sb.len > 0) {
            tooltip.set_markup (sb.str);
            return true;
        }

        return false;
    }

    public void select_and_scroll (int line, int start_col, int end_col) {
        var buffer = _text_view.buffer;

        if (line >= buffer.get_line_count ()) {
            return;
        }

        Gtk.TextIter start_iter;
        buffer.get_iter_at_line_offset (out start_iter, line, start_col);

        Gtk.TextIter end_iter;
        buffer.get_iter_at_line_offset (out end_iter, line, end_col);

        buffer.select_range (start_iter, end_iter);
        _text_view.scroll_to_iter (start_iter, 0.0, true, 0.5, 1.0);
    }
}
