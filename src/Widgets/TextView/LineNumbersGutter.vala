using Gtk;
using GtkSource;
using Cairo;

public class Iide.LineNumbersGutter : GtkSource.GutterRenderer {
    private weak Window window;

    private Pango.Layout? pango_layout = null;
    private double current_width = 12.0f; // Базовая ширина панели номеров строк
    private double symbol_width = 12.0f;
    private double horizontal_margin = 2.0f;

    public LineNumbersGutter (Window window) {
        Object ();
        this.window = window;

        // Выравниваем номера по правому краю ячейки (классический вид IDE)
        this.set_alignment_mode (GtkSource.GutterRendererAlignmentMode.CELL);
        this.set_xalign (1.0f); 
    }

    public void update_initial_width(int line_number_symbols_count, int font_size) {
        this.pango_layout = view.create_pango_layout ("");

        // Задаем текст номера строки
        this.symbol_width = (double) font_size * 6.0f / 10.0f;
        this.horizontal_margin = (double) font_size / 5.0f;
        this.current_width = line_number_symbols_count * font_size * 6.0f / 10.0f + 2.0f * horizontal_margin;

        queue_resize ();

        var gutter = (Gutter) get_parent ();
        if (gutter != null) {
            gutter.queue_allocate ();
        }
    }

    // Автоматический расчет ширины панели в зависимости от масштаба (зума)
    public override void measure (Gtk.Orientation orientation, int for_size, out int minimum, out int natural, out int minimum_baseline, out int natural_baseline) {
        minimum_baseline = natural_baseline = -1;
        if (orientation == Gtk.Orientation.HORIZONTAL) {
            minimum = natural = (int) Math.round (this.current_width);
        } else {
            minimum = natural = 0;
        }
    }

    public override void snapshot_line (Gtk.Snapshot snapshot, GtkSource.GutterLines lines, uint line) {
        // 1. Извлекаем реальный номер строки в документе (индексы с 0, поэтому для UI делаем +1)
        Gtk.TextIter current_line_iter;
        lines.get_iter_at_line (out current_line_iter, line);
        int real_line_number = current_line_iter.get_line () + 1;

        // 2. Получаем точные Y-координаты и высоту текущей строки на экране
        int cell_y, cell_height;
        lines.get_line_yrange (line, GtkSource.GutterRendererAlignmentMode.CELL, out cell_y, out cell_height);

        // Если строка скрыта фолдингом — её высота равна 0. 
        // Мгновенно выходим, исключая наложение номеров строк друг на друга.
        if (cell_height <= 0) {
            return;
        }

        var view = this.get_view ();
        if (view == null) 
            return;

        // ===================================================================
        // ЦEПОЧEЧНАЯ МАРШРУТИЗАЦИЯ ОТРИСОВКИ МАРКEРОВ (Сбор всех активных)
        // ===================================================================
        var active_render_services = new Gee.ArrayList<TextLineMarkService> ();
        var source_buffer = view.get_buffer () as GtkSource.Buffer;

        foreach (var service in this.window.marks_service) {
            // Опрашиваем GtkSource.Buffer на предмет категории текущего сервиса
            var marks = source_buffer.get_source_marks_at_line (current_line_iter.get_line (), service.category);
            
            if (marks != null && marks.length () > 0) {
                // УБРАНО: break;
                // СТАЛО: Собираем ВСЕ сервисы, у которых есть метка на этой строке!
                active_render_services.add (service);
            }
        }

        // ===================================================================

        // 3. ИНИЦИАЛИЗАЦИЯ ШРИФТА С УЧЕТОМ ЗУМА
        this.pango_layout = view.create_pango_layout ("");

        // Задаем текст номера строки
        string num_str = real_line_number.to_string ();
        this.pango_layout.set_text (num_str, -1);

        // Динамически корректируем ширину панели под разрядность чисел (100, 1000 и т.д.)
        Pango.Rectangle ink_rect, logical_rect;
        this.pango_layout.get_extents (out ink_rect, out logical_rect);
        int text_height_px = logical_rect.height / Pango.SCALE;

        // 4. ОТРИСОВКА НОМЕРА СТРОКИ ЧЕРЕЗ CAIRO
        var bounds = Graphene.Rect ();
        bounds.init (0.0f, (float) cell_y, (float) this.current_width, (float) cell_height);

        var cr = snapshot.append_cairo (bounds);
        
        // Координаты рисования с отступом в 6 пикселей от правого края панели
        double draw_x = this.horizontal_margin;
        double draw_y = (double) cell_y + ((cell_height - text_height_px) / 2.0);

        // Переменная-индикатор: менялся ли цвет шрифта номеров строк кастомным сервисом?
        bool text_was_rendered_by_service = false;

        if (!active_render_services.is_empty) {
            // Запускаем последовательную цепочку Cairo-отрисовки!
            foreach (var service in active_render_services) {
                // Каждый сервис накатывает свои прямоугольники и маркеры поверх предыдущего.
                // Чтобы они не перерисовывали текст, мы передаем null вместо pango_layout!
                service.render_func (cr, cell_y, cell_height, this.current_width, draw_x, draw_y, null);
            }

            // ПРИОРИТEТ ЦВEТА ТEКСТА: 
            // Если на строке одновременно и закладка (синяя), и брейкпоинт (красный),
            // давайте покрасим саму цифру номера строки в цвет последнего сработавшего сервиса (например, красный брейкпоинт)
            var priority_service = active_render_services.get (active_render_services.size - 1);
            
            // Вызываем render_func приоритетного сервиса ПOВТOРНO, но передаем параметры так,
            // чтобы он нарисовал СТРОГО текст (его лямбда просто сделает cairo_show_layout)
            priority_service.render_func (cr, cell_y, cell_height, this.current_width, draw_x, draw_y, this.pango_layout);
            
            text_was_rendered_by_service = true;
        }

        // 4. ДEФОЛТНЫЙ ТEКСТ (Отрабатывает только если на строке вообще пусто)
        if (!text_was_rendered_by_service) {
            cr.save ();
            // Стандартный серый цвет номеров строк
            cr.set_source_rgba (0.5, 0.5, 0.5, 0.6);
            cr.move_to (draw_x, draw_y);
            Pango.cairo_show_layout (cr, this.pango_layout);
            cr.restore ();
        }
    }
}
