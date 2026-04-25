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
    public SourceView source_view;
    private GtkSource.Map source_map;
    private FontZoomer font_zoomer;
    private Iide.SettingsService settings;
    private EditorStatusBar editor_status_bar;

    public Window window;
    public string uri { get; private set; }
    public SourceView text_view { get { return source_view; } }

    public bool is_modified { get { return ((GtkSource.Buffer) source_view.buffer).get_modified (); } }

    public signal void buffer_saved ();

    public TextView (GLib.File file, GtkSource.Buffer buffer, Window window) {
        Object ();
        this.uri = file.get_uri ();
        this.window = window;
        this.settings = Iide.SettingsService.get_instance ();

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

        source_view = new SourceView (window, uri, buffer);
        icon_name = source_view.icon_name;
        font_zoomer = new FontZoomer (source_view);

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

        // Connect to settings changes to apply to all open documents
        settings.editor_setting_changed.connect ((key) => {
            switch (key) {
                case "editor-font-size":
                    font_zoomer.set_zoom_level (settings.editor_font_size);
                    break;
                case "show-minimap":
                    toggle_minimap_visible (settings.show_minimap);
                    break;
            }
        });

        source_map = new GtkSource.Map ();
        // source_map.set_view (source_view);
        source_map.add_css_class ("textview-map");
        source_map.visible = settings.show_minimap;

        font_zoomer.zoom_changed.connect ((level) => {
            source_view.mark_renderer.set_icons_size (FontSizeHelper.get_size_for_zoom_level (level));
        });

        var scroll = new Gtk.ScrolledWindow ();
        scroll.hexpand = true;
        scroll.vexpand = true;

        scroll.set_child (source_view);

        // Чтобы миникарта понимала масштаб и положение,
        // она должна использовать тот же VAdjustment, что и ScrolledWindow редактора.
        source_map.set_view (source_view);

        // 3. Убедитесь, что миникарта не пытается скроллиться сама по себе
        source_map.vexpand = true;

        var subbox = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
        subbox.homogeneous = false;
        subbox.append (scroll);
        subbox.append (source_map);

        var font_map = Pango.CairoFontMap.get_default ();
        source_map.set_font_map (font_map);

        var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);

        box.append (subbox);

        this.editor_status_bar = new EditorStatusBar (source_view);
        box.append (this.editor_status_bar);
        if (source_view.ts_highlighter != null) {
            source_view.ts_highlighter.breadcrumbs_changed.connect (this.editor_status_bar.update_breadcrumbs);
        }
        this.editor_status_bar.breadcrumb_clicked.connect ((line, column) => {
            Gtk.TextIter iter;
            buffer.get_iter_at_line (out iter, (int) line);
            iter.set_line_index ((int) column);

            buffer.place_cursor (iter);
            source_view.scroll_to_iter (iter, 0.1, false, 0, 0.5);
            source_view.grab_focus ();
        });

        child = box;

        title = file.get_basename ();

        save_delegate = new Iide.SaveDelegate (this);
        modified = false;

        buffer.modified_changed.connect_after (() => {
            modified = buffer.get_modified ();
        });
        buffer.notify["cursor-position"].connect (() => {
            Gtk.TextIter insert, selection;
            buffer.get_selection_bounds (out insert, out selection);

            // 1. Обновляем позицию
            int line = insert.get_line ();
            int col = insert.get_line_index (); // Используем байтовый индекс для честности
            int sel_len = insert.get_offset () - selection.get_offset ();

            editor_status_bar.update_position (line, col, sel_len);
        });

        // Режим вставки (Insert/Overwrite)
        source_view.notify["overwrite"].connect (() => {
            editor_status_bar.update_mode (source_view.overwrite);
        });

        var main_adj = scroll.get_vadjustment ();
        var map_adj = source_map.get_vadjustment ();

        // 1. Связываем только ЗНАЧЕНИЕ (позицию), но не масштаб
        // Мы используем формулу пропорции, чтобы слайдер стоял там, где нужно
        main_adj.value_changed.connect (() => {
            // Рассчитываем процент прокрутки
            double main_range = main_adj.upper - main_adj.page_size;
            double map_range = map_adj.upper - map_adj.page_size;

            // Проверяем, что нам есть куда скроллить в основном вьювере
            if (main_range > 0) {
                // 1. Рассчитываем процент прокрутки (от 0.0 до 1.0)
                double percentage = main_adj.value / main_range;

                // 2. Рассчитываем целевое значение для миникарты
                double target_value = percentage * map_range;

                // 3. Применяем значение с ограничением (clamp),
                // чтобы избежать вылетов за границы при резком ресайзе
                map_adj.set_value (target_value.clamp (0, map_range));
            } else {
                // Если текст целиком влезает в экран, сбрасываем карту в начало
                map_adj.set_value (0);
            }
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
        source_view.grab_focus ();
    }

    public bool save () {
        try {
            var text = source_view.buffer.text;
            var file = GLib.File.new_for_uri (uri);
            file.replace_contents (text.data, null, false, GLib.FileCreateFlags.NONE, null);
            ((GtkSource.Buffer) source_view.buffer).set_modified (false);
            buffer_saved ();
        } catch (Error e) {
            critical (e.message);
        }
        return true;
    }

    public void update_diagnostics (Gee.ArrayList<IdeLspDiagnostic> diagnostics) {
        var text_buffer = (Gtk.TextBuffer) source_view.buffer;

        text_buffer.begin_user_action ();

        LspDiagnosticsMark.clear_mark_attributes (source_view);

        int line_count = text_buffer.get_line_count ();

        int lsp_error_count = 0;
        int lsp_warning_count = 0;
        int lsp_info_count = 0;

        foreach (var diag in diagnostics) {
            if (diag.start_line >= line_count) {
                continue;
            }

            Gtk.TextIter start_iter;
            text_buffer.get_iter_at_line (out start_iter, diag.start_line);

            var mark = new LspDiagnosticsMark.from_lsp_diagnostic (diag);
            text_buffer.add_mark (mark, start_iter); // Добавляем в буфер вручную

            switch (diag.severity) {
            case 1:
                lsp_error_count++;
                break;
            case 2:
                lsp_warning_count++;
                break;
            case 3:
            case 4:
                lsp_info_count++;
                break;
            }
        }

        text_buffer.end_user_action ();

        this.editor_status_bar.update_diagnostics (lsp_error_count, lsp_warning_count, lsp_info_count);
    }

    public void select_and_scroll (int line, int start_col, int end_col, bool is_new) {
        source_view.select_and_scroll (line, start_col, end_col, is_new);
    }
}