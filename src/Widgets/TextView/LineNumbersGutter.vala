using Gtk;
using GtkSource;
using Cairo;

namespace Iide {

    public class LineNumbersGutter : GtkSource.GutterRenderer {
        private Pango.Layout? pango_layout = null;
        private int current_width = 38; // Базовая ширина панели номеров строк

        public LineNumbersGutter () {
            Object ();
            // Выравниваем номера по правому краю ячейки (классический вид IDE)
            this.set_alignment_mode (GtkSource.GutterRendererAlignmentMode.CELL);
            this.set_xalign (1.0f); 
        }

        // Автоматический расчет ширины панели в зависимости от масштаба (зума)
        public override void measure (Gtk.Orientation orientation, int for_size, out int minimum, out int natural, out int minimum_baseline, out int natural_baseline) {
            minimum_baseline = natural_baseline = -1;
            if (orientation == Gtk.Orientation.HORIZONTAL) {
                minimum = natural = this.current_width;
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
            if (view == null) return;

            // 3. ИНИЦИАЛИЗАЦИЯ ШРИФТА С УЧЕТОМ ЗУМА
            this.pango_layout = view.create_pango_layout ("");
            //  var font_desc = view.get_font_desc ();
            //  if (font_desc != null) {
            //      this.pango_layout.set_font_description (font_desc);
            //  } else {
            //      this.pango_layout.set_font_description (Pango.FontDescription.from_string ("Monospace 11"));
            //  }

            // Задаем текст номера строки
            string num_str = real_line_number.to_string ();
            this.pango_layout.set_text (num_str, -1);

            // Динамически корректируем ширину панели под разрядность чисел (100, 1000 и т.д.)
            Pango.Rectangle ink_rect, logical_rect;
            this.pango_layout.get_extents (out ink_rect, out logical_rect);
            int text_width_px = logical_rect.width / Pango.SCALE;
            int text_height_px = logical_rect.height / Pango.SCALE;

            // Ширина текста + аккуратные отступы по краям
            int calculated_width = text_width_px + 12;
            if (this.current_width != calculated_width && calculated_width > 38) {
                this.current_width = calculated_width;
                view.queue_resize (); // Форсируем пересчет ширины левой панели
            }

            // 4. ОТРИСОВКА НОМЕРА СТРОКИ ЧЕРЕЗ CAIRO
            var bounds = Graphene.Rect ();
            bounds.init (0.0f, (float) cell_y, (float) this.current_width, (float) cell_height);

            var cr = snapshot.append_cairo (bounds);
            
            // Цвет номеров строк: неконтрастный серый (Alpha 60%)
            cr.set_source_rgba (0.5, 0.5, 0.5, 0.6);

            // Координаты рисования с отступом в 6 пикселей от правого края панели
            double draw_x = (double) this.current_width - text_width_px - 6.0;
            double draw_y = (double) cell_y + ((cell_height - text_height_px) / 2.0);

            cr.move_to (draw_x, draw_y);
            Pango.cairo_show_layout (cr, this.pango_layout);
        }
    }
}
