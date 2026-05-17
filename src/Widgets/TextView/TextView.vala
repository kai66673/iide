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
    private Gtk.DrawingArea indent_lines_canvas;

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
        source_view.bottom_margin = 400;

        // icon_name = source_view.icon_name;
        set_icon_name (ImageFactory.icon_name_for_file (file));
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
        this.indent_lines_canvas = new Gtk.DrawingArea ();
        this.indent_lines_canvas.can_target = false;
        this.overlay.add_overlay (this.indent_lines_canvas);

        var doc = this.source_view.document as Iide.TreeSitterDocument;
        if (doc != null && doc.ts_highlighter != null) {
            this.indent_lines_canvas.set_draw_func (this.draw_indent_lines);
            doc.ts_highlighter.folding_structure_updated.connect ((blocks) => {
                // Дерево обновилось -> принудительно стираем старые линии отступов и чертим новые
                this.indent_lines_canvas.queue_draw ();
            });
            buffer.notify["cursor-position"].connect (() => {
                // Принудительно заставляем холст линий отступов перерисоваться,
                // чтобы мгновенно обновить подсвеченную линию
                this.indent_lines_canvas.queue_draw ();
            });
        }

        this.source_view.get_vadjustment ().value_changed.connect (() => { this.indent_lines_canvas.queue_draw (); });
        this.source_view.get_hadjustment ().value_changed.connect (() => { this.indent_lines_canvas.queue_draw (); });

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
    }

    private void draw_indent_lines (Gtk.DrawingArea drawing_area, Cairo.Context cr, int width, int height) {
        // Получаем доступ к документу и подсвечнику
        var doc = this.source_view.document as Iide.TreeSitterDocument;
        if (doc == null || doc.ts_highlighter == null) return;

        var ts_blocks = doc.ts_highlighter.get_cached_indent_blocks ();
        if (ts_blocks.size == 0) return;

        // Настройка стиля линий отступов (Тонкий полупрозрачный серый цвет)
        cr.set_source_rgba (0.5, 0.5, 0.5, 0.25);
        cr.set_line_width (1.0);

        // Считаем ширину одного таба в пикселях на основе текущего шрифта
        double tab_width_px = this.calculate_tab_width_pixels ();
        int left_margin = this.source_view.get_left_margin ();
        double h_scroll = this.source_view.get_hadjustment ().get_value ();

        // ===================================================================
        // ХОТФИКС: ВЫЧИСЛЕНИЕ ШИРИНЫ ГУТТЕРОВ
        // Мы запрашиваем у текстового поля ширину левой служебной панели (Gutter Window)
        int gutter_width = 0;
        
        // В GTK 4 правильный способ получить физическую ширину левой области:
        // Мы берем левый гутер и запрашиваем его ширину через распределение (allocation)
        var left_gutter = this.source_view.get_gutter (Gtk.TextWindowType.LEFT);
        if (left_gutter != null) {
            // Извлекаем реальную ширину виджета панели на экране
            gutter_width = left_gutter.get_width ();
        }
        // ===================================================================

        // 1. Получаем строку, на которой сейчас стоит курсор
        Gtk.TextIter cursor_iter;
        var buffer = this.source_view.get_buffer ();
        buffer.get_iter_at_mark (out cursor_iter, buffer.get_insert ());
        int cursor_line = cursor_iter.get_line ();

        // 2. Находим активный блок для строки курсора
        // Используем публичный метод, который мы уже написали в вашем Gutter
        var active_highlighter_block = this.source_view.folding_gutter.find_deepest_block_for_line (cursor_line);

        foreach (var block in ts_blocks) {
            Gtk.TextIter start_iter, end_iter;
            this.source_view.get_buffer ().get_iter_at_line (out start_iter, block.start_line);
            this.source_view.get_buffer ().get_iter_at_line (out end_iter, block.end_line);

            // Получаем физические координаты Y внутри буфера
            int start_y_buf, start_height;
            int end_y_buf, end_height;
            
            this.source_view.get_line_yrange (start_iter, out start_y_buf, out start_height);
            this.source_view.get_line_yrange (end_iter, out end_y_buf, out end_height);

            // СВЕРНУТЫЙ БЛОК: Если высота строки равна 0 — код скрыт фолдингом.
            // Пропускаем отрисовку этой линии, чтобы она не торчала из-под свернутого [+]
            if (start_height <= 0 || end_height <= 0) continue;

            // Переводим внутренние координаты буфера в физические пиксели окна оверлея
            int win_x, win_y_start, win_y_end;
            this.source_view.buffer_to_window_coords (Gtk.TextWindowType.TEXT, 0, start_y_buf, out win_x, out win_y_start);
            this.source_view.buffer_to_window_coords (Gtk.TextWindowType.TEXT, 0, end_y_buf, out win_x, out win_y_end);

            // Расчет X-координаты линии: базовый отступ + (уровень вложенности AST * пиксели таба)
            // Хотфикс размытия Cairo: добавляем +0.5, чтобы линия легла ровно на сетку пикселей монитора
            double line_x = gutter_width + left_margin + (block.indent_level * tab_width_px) - h_scroll + 0.5;

            // Оптимизация: не рисуем линии, которые находятся за пределами видимого экрана по вертикали
            if (win_y_start > height || (win_y_end + end_height) < 0) continue;

            double draw_y_start = double.max (win_y_start, 0.0);
            double draw_y_end = double.min (win_y_end + end_height, (double) height);

            // ВЫЧИСЛЕНИЕ ДИНАМИЧЕСКОГО ЦВЕТА ЛИННИИ:
            // Линия подсвечивается ярким цветом, если блок строки курсора совпадает с текущим отрисовываемым блоком
            // ИЛИ текущий блок является родителем для блока курсора (чтобы линия шла до верха)
            bool is_active_line = false;
            if (active_highlighter_block != null) {
                if (block.start_line == active_highlighter_block.start_line && block.end_line == active_highlighter_block.end_line) {
                    is_active_line = true;
                } else if (cursor_line >= block.start_line && cursor_line <= block.end_line && active_highlighter_block.indent_level > block.indent_level) {
                    // Если курсор ушел глубже во вложенность, внешнюю родительскую линию тоже подсвечиваем
                    is_active_line = true;
                }
            }

            if (is_active_line) {
                cr.set_source_rgba (0.2, 0.6, 1.0, 0.7); // Контрастный синий для активного отступа
                cr.set_line_width (1.2); // Делаем активную линию чуть толще для акцента
            } else {
                cr.set_source_rgba (0.5, 0.5, 0.5, 0.25); // Блеклый серый по умолчанию
                cr.set_line_width (1.0);
            }
            
            // Рисуем монолитную вертикальную линию от начала до конца блока кода
            cr.move_to (line_x, draw_y_start);
            cr.line_to (line_x, draw_y_end);
            cr.stroke ();
        }
    }

    private double calculate_tab_width_pixels () {
        // TODO: Implement real metrix char width...
        double char_width_px = 0.6f * FontSizeHelper.get_size_for_zoom_level (settings.editor_font_size);

        uint tab_width_chars = this.source_view.get_tab_width ();
        if (tab_width_chars == 0) tab_width_chars = 4;

        return char_width_px * tab_width_chars;
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

    public void update_diagnostics (Gee.ArrayList<LspDiagnostic> diagnostics) {
        var text_buffer = (Gtk.TextBuffer) source_view.buffer;

        text_buffer.begin_user_action ();

        LspDiagnosticsMark.clear_mark_attributes (source_view);

        int line_count = text_buffer.get_line_count ();

        int lsp_error_count = 0;
        int lsp_warning_count = 0;

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
            case 2: case 3: case 4:
                lsp_warning_count++;
                break;
            }
        }

        text_buffer.end_user_action ();

        this.editor_status_bar.update_diagnostics (lsp_error_count, lsp_warning_count);
    }

    public void select_and_scroll (int line, int start_col, int end_col, bool is_new) {
        source_view.select_and_scroll (line, start_col, end_col, is_new);
    }
}