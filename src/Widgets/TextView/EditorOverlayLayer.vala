/*
*/

using GLib;
using Gtk;
using Gdk;
using Cairo;

// Структура для отслеживания кликабельных зон на холсте оверлея
public struct Iide.ClickableIndicator {
    public Gdk.Rectangle rect;
    public int start_line;
}

public class Iide.EditorOverlayLayer : Gtk.DrawingArea {
    // Ссылка на родительский TextView для расчета координат и буфера
    private unowned SourceView source_view;
    
    // Внутренний кэш зон кликов и тултипов
    private Gee.ArrayList<ClickableIndicator?> visible_indicators;

    private Iide.SettingsService settings;

    public EditorOverlayLayer (SourceView view) {
        Object ();
        this.source_view = view;
        this.visible_indicators = new Gee.ArrayList<ClickableIndicator?> ();
        this.settings = Iide.SettingsService.get_instance ();

        this.bind_to_source_view ();
    }

    private void bind_to_source_view() {
        this.can_target = false;

        var doc = this.source_view.document as Iide.TreeSitterDocument;
        if (doc != null && doc.ts_highlighter != null) {
            // Назначаем функцию отрисовки (GTK4 стиль)
            this.set_draw_func (this.draw_indent_lines);
            doc.ts_highlighter.folding_structure_updated.connect ((blocks) => {
                // Дерево обновилось -> принудительно стираем старые линии отступов и чертим новые
                this.queue_draw ();
            });
            this.source_view.buffer.notify["cursor-position"].connect (() => {
                // Принудительно заставляем холст линий отступов перерисоваться,
                // чтобы мгновенно обновить подсвеченную линию
                this.queue_draw ();
            });
            this.source_view.folding_gutter.fold_state_changed.connect (() => {
                // Мгновенно обновляем линии и плашки "..." при любом клике на панели фолдинга
                this.queue_draw ();
                this.queue_resize ();
            });

            // Инициализируем жест клика НА ТЕКСТОВОМ ПОЛЕ, а не на холсте
            var click_gesture = new Gtk.GestureClick ();

            // КРИТИЧЕСКИЙ ШАГ ДЛЯ GTK 4:
            // Настраиваем фазу распространения. CAPTURE означает, что наше текстовое поле 
            // сначала даст шанс этому жесту проверить координаты клика ДО того, 
            // как включится стандартная логика выделения текста, зума или скролла.
            click_gesture.set_propagation_phase (Gtk.PropagationPhase.CAPTURE);

            click_gesture.pressed.connect ((n_presses, x, y) => {
                foreach (var indicator in this.visible_indicators) {
                    // Проверяем попадание клика в рамки плашки "..."
                    if (x >= indicator.rect.x && x <= (indicator.rect.x + indicator.rect.width) &&
                        y >= indicator.rect.y && y <= (indicator.rect.y + indicator.rect.height)) {
                        // Клик попал в плашку "..." — разворачиваем код!
                        var folding_gutter = this.source_view.folding_gutter;
                        
                        Gtk.TextIter trigger_iter;
                        this.source_view.get_buffer ().get_iter_at_line (out trigger_iter, indicator.start_line);
                        
                        folding_gutter.activate (trigger_iter, Gdk.Rectangle (), 1, Gdk.ModifierType.NO_MODIFIER_MASK, 1);
                        
                        // Заставляем оверлей принудительно стереть плашку "..." на этом же кадре
                        this.queue_draw ();

                        // Останавливаем дальнейшее распространение клика в GTK, 
                        // чтобы под плашкой случайно не выделился текст или не прыгнул курсор
                        click_gesture.set_state (Gtk.EventSequenceState.CLAIMED);
                        return; 
                    }
                }

                // Если клик был мимо плашки "..." — мы просто отпускаем событие.
                // Благодаря фазе CAPTURE и отсутствию CLAIMED, GTK 4 передаст этот клик 
                // в штатный движок GtkSourceView. Выделение текста, курсор, зум и скролл 
                // продолжат работать идеально и нативно!
                click_gesture.set_state (Gtk.EventSequenceState.DENIED);
            });

            // Добавляем контроллер на физический виджет текстового поля
            this.source_view.add_controller (click_gesture);

        }

        this.source_view.get_vadjustment ().value_changed.connect (() => { this.queue_draw (); });
        this.source_view.get_hadjustment ().value_changed.connect (() => { this.queue_draw (); });
    }

    private double calculate_tab_width_pixels () {
        // TODO: Implement real metrix char width...
        double char_width_px = 0.6f * FontSizeHelper.get_size_for_zoom_level (settings.editor_font_size);

        uint tab_width_chars = this.source_view.get_tab_width ();
        if (tab_width_chars == 0) tab_width_chars = 4;

        return char_width_px * tab_width_chars;
    }

    private void draw_rounded_rectangle (Cairo.Context cr, double x, double y, double width, double height, double radius) {
        double degrees = Math.PI / 180.0;

        cr.new_sub_path ();
        cr.arc (x + width - radius, y + radius, radius, -90 * degrees, 0 * degrees);
        cr.arc (x + width - radius, y + height - radius, radius, 0 * degrees, 90 * degrees);
        cr.arc (x + radius, y + height - radius, radius, 90 * degrees, 180 * degrees);
        cr.arc (x + radius, y + radius, radius, 180 * degrees, 270 * degrees);
        cr.close_path ();
    }

    private void draw_indent_lines (Gtk.DrawingArea drawing_area, Cairo.Context cr, int width, int height) {
        this.visible_indicators.clear ();
        
        var doc = this.source_view.document as Iide.TreeSitterDocument;
        if (doc == null || doc.ts_highlighter == null) return;

        var ts_blocks = doc.ts_highlighter.get_cached_indent_blocks ();
        var folding_gutter = this.source_view.folding_gutter;
        if (ts_blocks.size == 0) return;

        cr.set_source_rgba (0.5, 0.5, 0.5, 0.25);
        cr.set_line_width (1.0);

        double tab_width_px = this.calculate_tab_width_pixels ();
        uint tab_width_chars = this.source_view.get_tab_width ();
        if (tab_width_chars == 0) tab_width_chars = 4;
        int left_margin = this.source_view.get_left_margin ();
        double h_scroll = this.source_view.get_hadjustment ().get_value ();

        int gutter_width = 0;
        var left_gutter = this.source_view.get_gutter (Gtk.TextWindowType.LEFT);
        if (left_gutter != null) {
            gutter_width = left_gutter.get_width ();
        }

        foreach (var block in ts_blocks) {
            Gtk.TextIter start_iter;
            this.source_view.get_buffer ().get_iter_at_line (out start_iter, block.start_line);

            // 1. Проверяем геометрию ТОЛЬКО для строки заголовка
            int start_y_buf, start_height;
            this.source_view.get_line_yrange (start_iter, out start_y_buf, out start_height);

            // Если сам заголовок скрыт (находится внутри другого свернутого блока) — полностью пропускаем
            if (start_height <= 0) continue;

            // Переводим Y-координату начала блока в пиксели окна оверлея
            int win_x, win_y_start;
            this.source_view.buffer_to_window_coords (Gtk.TextWindowType.TEXT, 0, start_y_buf, out win_x, out win_y_start);

            // Запрашиваем состояние свернутости из нашего стабильного Gutter-а
            bool is_collapsed = folding_gutter.is_line_collapsed_by_number (block.start_line);

            // 1. Получаем строку, на которой сейчас стоит курсор
            Gtk.TextIter cursor_iter;
            var buffer = this.source_view.get_buffer ();
            buffer.get_iter_at_mark (out cursor_iter, buffer.get_insert ());
            int cursor_line = cursor_iter.get_line ();

            // 2. Находим активный блок для строки курсора
            // Используем публичный метод, который мы уже написали в вашем Gutter
            var active_highlighter_block = folding_gutter.find_deepest_block_for_line (cursor_line);

            if (is_collapsed) {
                // === МАСШТАБИРУЕМЫЙ РЕНДЕРИНГ ПЛАШКИ "..." ===
                
                Gtk.TextIter eol_iter = start_iter;
                eol_iter.forward_to_line_end ();
                
                Gdk.Rectangle eol_rect;
                this.source_view.get_iter_location (eol_iter, out eol_rect);
                
                int win_eol_x, win_eol_y;
                this.source_view.buffer_to_window_coords (Gtk.TextWindowType.TEXT, eol_rect.x, eol_rect.y, out win_eol_x, out win_eol_y);

                double line_h = (double) start_height;
                double btn_h = line_h * 0.65;             
                double btn_w = btn_h * 1.7;               
                double font_size = line_h * 0.45;         

                // Физическая координата на оверлее
                double btn_x = gutter_width + win_eol_x + (line_h * 0.3); 
                double btn_y = win_eol_y + ((line_h - btn_h) / 2.0);

                // ===================================================================
                // ИСПРАВЛЕНИЕ: Сохраняем в кэш кликов ПОЛНУЮ координату btn_x (с гутером).
                // Теперь рамка попадания мыши встанет ровно туда, где плашка отрисована визуально!
                var click_zone = ClickableIndicator () {
                    rect = Gdk.Rectangle () { 
                        x = (int) btn_x, 
                        y = (int) btn_y, 
                        width = (int) btn_w, 
                        height = (int) btn_h 
                    },
                    start_line = block.start_line
                };
                this.visible_indicators.add (click_zone);
                // ===================================================================

                cr.save ();
                
                // Отрисовка фона плашки
                cr.set_source_rgba (0.5, 0.5, 0.5, 0.15); 
                double radius = btn_h * 0.25;
                this.draw_rounded_rectangle (cr, btn_x, btn_y, btn_w, btn_h, radius);
                cr.fill ();
                
                // Отрисовка границы
                this.draw_rounded_rectangle (cr, btn_x, btn_y, btn_w, btn_h, radius);
                cr.set_source_rgba (0.5, 0.5, 0.5, 0.4); 
                cr.set_line_width (1.0);
                cr.stroke ();

                // Отрисовка текста "..."
                cr.set_source_rgba (0.4, 0.4, 0.4, 1.0);
                cr.select_font_face ("Monospace", Cairo.FontSlant.NORMAL, Cairo.FontWeight.BOLD);
                cr.set_font_size (font_size);

                Cairo.TextExtents extents;
                cr.text_extents ("...", out extents);
                double text_x = btn_x + ((btn_w - extents.width) / 2.0) - extents.x_bearing;
                double text_y = btn_y + ((btn_h - extents.height) / 2.0) - extents.y_bearing;

                cr.move_to (text_x, text_y);
                cr.show_text ("...");
                
                cr.restore ();

                continue; 
            }

            // ===================================================================
            // ДОРАБОТКА: ОТРИСОВКА ЗНАЧКА СВОРЧИВАНИЯ "[-]" ДЛЯ РАЗВЕРНУТОГО БЛОКА
            // ===================================================================
            // Отрендерим интерактивную кнопку минуса в конце первой строки блока.
            // Показываем её, если строка или блок активны (например, курсор внутри), 
            // чтобы не засорять интерфейс лишними иконками на каждой строчке.
            bool should_show_minus = (active_highlighter_block != null && 
                                      cursor_line >= block.start_line && 
                                      cursor_line <= block.end_line);

            if (should_show_minus) {
                Gtk.TextIter eol_iter = start_iter;
                eol_iter.forward_to_line_end ();
                
                Gdk.Rectangle eol_rect;
                this.source_view.get_iter_location (eol_iter, out eol_rect);
                
                int win_eol_x, win_eol_y;
                this.source_view.buffer_to_window_coords (Gtk.TextWindowType.TEXT, eol_rect.x, eol_rect.y, out win_eol_x, out win_eol_y);

                double line_h = (double) start_height;
                double btn_h = line_h * 0.55; // Чуть меньше, чем "...", чтобы смотрелось аккуратно
                double btn_w = btn_h;         // Квадратная кнопка
                
                double btn_x = gutter_width + win_eol_x + (line_h * 0.4); 
                double btn_y = win_eol_y + ((line_h - btn_h) / 2.0);

                // Добавляем в ваш существующий кэш зон кликов. 
                // Обработчик кликов автоматически подхватит эту зону и передаст start_line на сворачивание.
                var click_zone = ClickableIndicator () {
                    rect = Gdk.Rectangle () { 
                        x = (int) btn_x, 
                        y = (int) btn_y, 
                        width = (int) btn_w, 
                        height = (int) btn_h 
                    },
                    start_line = block.start_line
                };
                this.visible_indicators.add (click_zone);

                cr.save ();
                
                // Делаем легкую полупрозрачную подложку кнопки
                cr.set_source_rgba (0.5, 0.5, 0.5, 0.1); 
                double radius = btn_h * 0.2;
                this.draw_rounded_rectangle (cr, btn_x, btn_y, btn_w, btn_h, radius);
                cr.fill ();
                
                // Отрисовка рамки значка
                this.draw_rounded_rectangle (cr, btn_x, btn_y, btn_w, btn_h, radius);
                cr.set_source_rgba (0.5, 0.5, 0.5, 0.35); 
                cr.set_line_width (1.0);
                cr.stroke ();

                // Рисуем знак минус "—" по центру квадрата
                cr.set_source_rgba (0.4, 0.4, 0.4, 0.8);
                cr.set_line_width (1.2);
                cr.move_to (btn_x + (btn_w * 0.25), btn_y + (btn_h * 0.5));
                cr.line_to (btn_x + (btn_w * 0.75), btn_y + (btn_h * 0.5));
                cr.stroke ();

                cr.restore ();
            }

            // ===================================================================
            // ОТРИСОВКА ЛИНЕЙ ОТСТУПОВ ДЛЯ РАЗВЕРНУТОГО БЛОКА
            // ===================================================================
            // Самый внешний уровень (col 0) не рисуем вообще, пока виден gutter
            // фолдинга — его роль выполняют маркеры сворачивания в gutter'е
            if (block.indent_level == 0 && folding_gutter.visible) continue;

            // Логика цвета (активная/пассивная линия из предыдущего шага)
            bool is_active_line = false;
            if (active_highlighter_block != null) {
                if (block.start_line == active_highlighter_block.start_line && block.end_line == active_highlighter_block.end_line) {
                    is_active_line = true;
                } else if (cursor_line >= block.start_line && cursor_line <= block.end_line && active_highlighter_block.indent_level > block.indent_level) {
                    is_active_line = true;
                }
            }

            if (is_active_line) {
                cr.set_source_rgba (0.2, 0.6, 1.0, 0.7); 
                cr.set_line_width (1.2); 
            } else {
                cr.set_source_rgba (0.5, 0.5, 0.5, 0.25); 
                cr.set_line_width (1.0);
            }

            double line_x = gutter_width + left_margin + (block.indent_level * tab_width_px) - h_scroll + 0.5;
            if (line_x < gutter_width) continue;
            if (win_y_start > height) continue;

            // Линия рисуется НЕ сплошным штрихом на всю высоту блока, а сегментами:
            // строки, в которых текст задевает колонку гида (заголовок вида `if (x) {`,
            // `} else {` и т.п.), вырезаются. Колонка гида символьная:
            // indent_level * tab_width, пиксельных вычислений по тексту не делаем.
            int guide_col = block.indent_level * (int) tab_width_chars;

            double seg_top = 0.0;
            double seg_bottom = 0.0;
            bool seg_open = false;

            for (int ln = block.start_line; ln <= block.end_line; ln++) {
                Gtk.TextIter line_iter;
                buffer.get_iter_at_line (out line_iter, ln);

                int line_y_buf, line_height;
                this.source_view.get_line_yrange (line_iter, out line_y_buf, out line_height);

                // Скрытая строка (внутри чужого свернутого блока) — разрыв сегмента
                if (line_height <= 0) {
                    if (seg_open) {
                        cr.move_to (line_x, seg_top);
                        cr.line_to (line_x, seg_bottom);
                        cr.stroke ();
                        seg_open = false;
                    }
                    continue;
                }

                int win_y_line;
                this.source_view.buffer_to_window_coords (Gtk.TextWindowType.TEXT, 0, line_y_buf, out win_x, out win_y_line);

                // Строки идут сверху вниз — всё, что ниже вьюпорта, нам не нужно
                if (win_y_line > height) break;

                double line_bottom = double.min (win_y_line + (double) line_height, (double) height);

                // Строки выше вьюпорта: пересечение с текстом над экраном не важно —
                // сегмент все равно клипнется в 0 первой видимой строкой
                if (line_bottom <= 0.0) continue;

                double line_top = double.max ((double) win_y_line, 0.0);

                // Текст строки налезает на колонку гида — здесь линии быть не должно
                if (this.line_intersects_guide (buffer, ln, guide_col, tab_width_chars)) {
                    if (seg_open) {
                        cr.move_to (line_x, seg_top);
                        cr.line_to (line_x, seg_bottom);
                        cr.stroke ();
                        seg_open = false;
                    }
                    continue;
                }

                if (!seg_open) {
                    seg_top = line_top;
                    seg_open = true;
                }
                seg_bottom = line_bottom;
            }

            if (seg_open) {
                cr.move_to (line_x, seg_top);
                cr.line_to (line_x, seg_bottom);
                cr.stroke ();
            }
        }
    }

    // Проверяет, задевает ли текст строки колонку вертикального гида отступов.
    // Колонки считаются в символах: пробел = 1, таб = следующий таб-стоп.
    // Края диапазона текста включаются: гид в том числе на левом краю первого
    // символа строки тоже считается пересечением (режем строку).
    private bool line_intersects_guide (Gtk.TextBuffer buffer, int line_no, int guide_col, uint tab_width_chars) {
        Gtk.TextIter iter;
        buffer.get_iter_at_line (out iter, line_no);

        Gtk.TextIter eol_iter = iter;
        eol_iter.forward_to_line_end ();
        string line_text = buffer.get_text (iter, eol_iter, false);

        int col = 0;
        int first_col = -1;
        int last_col = -1;

        int char_index = 0;
        while (true) {
            unichar ch;
            if (!line_text.get_next_char (ref char_index, out ch)) break;

            if (ch == '\t') {
                // Колонка следующего таб-стопа
                col = (col / (int) tab_width_chars + 1) * (int) tab_width_chars;
            } else if (ch.isspace ()) {
                col += 1;
            } else {
                if (first_col < 0) first_col = col;
                last_col = col;
                col += 1;
            }
        }

        // Пустая строка (или из одних пробелов) — пересечения нет
        if (first_col < 0) return false;

        // Гид внутри диапазона текста с обеих сторон включительно: задевает и
        // случай, когда гид стоит ровно на левом краю первого символа строки
        return first_col <= guide_col && guide_col <= last_col;
    }
        
    // Публичный метод, чтобы TextView мог передавать сюда клики мыши, если они обрабатываются на его уровне
    public Gee.ArrayList<ClickableIndicator?> get_visible_indicators () { return this.visible_indicators; }
}
