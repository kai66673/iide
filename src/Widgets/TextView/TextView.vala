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
    private Gtk.Overlay overlay;
    private EditorOverlayLayer indent_lines_canvas;

    private GtkSource.Map source_map;
    private FontZoomer font_zoomer;
    private Iide.SettingsService settings;
    private EditorStatusBar editor_status_bar;

    public Window window;
    public string uri { get; private set; }

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
        source_view.bottom_margin = 400;

        // icon_name = source_view.icon_name;
        set_icon_name (ImageFactory.icon_name_for_file (file));
        font_zoomer = new FontZoomer (source_view);

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
            source_view.line_numbers_gutter.update_initial_width (
                this.source_view.buffer.get_line_count().to_string ().length,
                FontSizeHelper.get_size_for_zoom_level (settings.editor_font_size)
            );
            source_view.mark_renderer.set_icons_size (FontSizeHelper.get_size_for_zoom_level (level));
            source_view.folding_gutter.set_icons_size (FontSizeHelper.get_size_for_zoom_level (level));
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

        this.overlay = new Gtk.Overlay ();
        this.overlay.set_child (scroll);
        this.indent_lines_canvas = new EditorOverlayLayer (this.source_view);
        this.overlay.add_overlay (this.indent_lines_canvas);
        this.source_view.set_overlay (this.indent_lines_canvas);

        var subbox = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
        subbox.homogeneous = false;
        subbox.append (this.overlay);
        subbox.append (source_map);

        var font_map = Pango.CairoFontMap.get_default ();
        source_map.set_font_map (font_map);

        var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);

        box.append (subbox);

        this.editor_status_bar = new EditorStatusBar (source_view);
        box.append (this.editor_status_bar);
        source_view.breadcrumbs_changed.connect (this.editor_status_bar.update_breadcrumbs);

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

        // Обработка Esc для скрытия панели поиска:
        var esc_key_ctrl = new Gtk.EventControllerKey ();

        // ВАЖНО: Используем фазу CAPTURE, чтобы перехватить Esc до того, 
        // как текстовый буфер попытается обработать его как-то по-своему.
        esc_key_ctrl.set_propagation_phase (Gtk.PropagationPhase.CAPTURE);

        esc_key_ctrl.key_pressed.connect ((keyval, keycode, state) => {
            if (keyval == Gdk.Key.Escape) {
                // Запрашиваем родительский статус-бар у этого TextView.
                // Предполагается, что ваш EditorStatusBar доступен через свойство/метод, 
                // либо лежит в той же иерархии контейнеров (например, у них общий родитель Box).
                // Если у вас статус-бар сохранен в приватном поле text_view_container.status_bar:
                if (this.editor_status_bar != null) {
                    
                    // Проверяем, открыт ли сейчас поиск (чтобы Esc не срабатывал вхолостую).
                    // Для этого можно добавить простой геттер в EditorStatusBar или проверять visible_child_name
                    if (this.editor_status_bar.is_search_bar_visible ()) {
                        this.editor_status_bar.hide_search_bar ();
                        
                        // Возвращаем true, полностью останавливая дальнейшее распространение Esc в GTK
                        return true; 
                    }
                }
            }
            return false; // Все остальные клавиши пропускаем дальше свободно
        });

        this.add_controller (esc_key_ctrl);
    }

    public void show_search_bar () {
        this.editor_status_bar.show_search_bar ();
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
            TextLineMarkService.get_instance ().update_buffer_marks (
                this.uri, this.source_view.buffer
            );
        } catch (Error e) {
            critical (e.message);
        }
        return true;
    }

    public void update_diagnostics (string server_name, Gee.ArrayList<LspDiagnosticPair?> diagnostics) {
        var text_buffer = (Gtk.TextBuffer) source_view.buffer;

        text_buffer.begin_user_action ();

        LspDiagnosticsMark.clear_mark_attributes (server_name, source_view);

        int line_count = text_buffer.get_line_count ();

        int lsp_error_count = 0;
        int lsp_warning_count = 0;

        if (diagnostics.size > 0) {
            var new_marks = new Gee.ArrayList<LspDiagnosticsMark> ();
            foreach (var diag in diagnostics) {
                if (diag.diagnostic.start_line >= line_count) {
                    continue;
                }

                Gtk.TextIter start_iter;
                text_buffer.get_iter_at_line (out start_iter, diag.diagnostic.start_line);

                var mark = new LspDiagnosticsMark.from_lsp_diagnostic (diag.diagnostic, diag.raw_json);
                text_buffer.add_mark (mark, start_iter); // Добавляем в буфер вручную
                new_marks.add (mark);

                switch (diag.diagnostic.severity) {
                case 1:
                    lsp_error_count++;
                    break;
                case 2: case 3: case 4:
                    lsp_warning_count++;
                    break;
                }
            }

            if (new_marks.size > 0) {
                source_view.lsp_marks.set (server_name, new_marks);
            }
        }

        text_buffer.end_user_action ();

        this.editor_status_bar.update_diagnostics (server_name, lsp_error_count, lsp_warning_count);
    }

    public void select_and_scroll (int line, int start_col, int end_col, bool is_new) {
        source_view.select_and_scroll (line, start_col, end_col, is_new);
    }
    
    public void toggle_bookmark_on_current_line () {
        this.source_view.toggle_bookmark_on_current_line ();

        // Если документ не модифицирован (сохранен), обновляем все закладки документа
        if (!this.is_modified) {
            TextLineMarkService.get_instance ().update_buffer_marks (
                this.source_view.uri, this.source_view.buffer
            );
        }
    }
}