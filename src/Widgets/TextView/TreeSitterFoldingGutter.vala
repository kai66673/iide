/*
*/
using Gtk;
using GtkSource;
using Cairo;

public class Iide.TreeSitterFoldingGutter : GtkSource.GutterRenderer {
    private string folding_tag_name = "$FOLD_HIDE";
    private int current_icon_size = 16;

    // Локальная копия структуры блоков файла
    private Gee.List<IndentBlock?> file_blocks;

    public TreeSitterFoldingGutter () {
        Object ();
        this.file_blocks = new Gee.ArrayList<IndentBlock?> ();
        this.set_alignment_mode (GtkSource.GutterRendererAlignmentMode.CELL);
    }

    public void set_icons_size (int size) {
        if (current_icon_size == size) {
            return;
        }
        current_icon_size = size;
        queue_resize ();

        var gutter = (Gutter) get_parent ();
        if (gutter != null) {
            gutter.queue_allocate ();
        }
    }

    // Метод вызывается из SourceView при обновлении AST дерева
    public void update_blocks_data (Gee.List<IndentBlock?> blocks) {
        LoggerService.get_instance ().info ("FOLDING", "blocks count = %d".printf (blocks.size));
        this.file_blocks = blocks;
        this.queue_draw (); // Перерисовываем панель под новые маркеры
    }

    public override bool query_activatable (Gtk.TextIter iter, Gdk.Rectangle area) {
        int line = iter.get_line ();
        
        // Метод разрешает кликать ТОЛЬКО по тем строкам, где реально начинается блок.
        // Это предотвращает ложные клики по пустым местам транзитных линий.
        return this.check_if_block_starts (line);
    }

    public override void measure (Gtk.Orientation orientation, int for_size, out int minimum, out int natural, out int minimum_baseline, out int natural_baseline) {
        minimum_baseline = natural_baseline = -1;
        if (orientation == Gtk.Orientation.HORIZONTAL) {
            minimum = natural = current_icon_size;
        } else {
            minimum = natural = 0;
        }
    }

    public override void snapshot (Gtk.Snapshot snapshot) {
        // Получаем физические размеры всего рендерера гутера
        int width = this.get_width ();
        int height = this.get_height ();

        // Если панель свернута, скрыта или имеет нулевую высоту — 
        // полностью блокируем рендеринг, чтобы предотвратить спам GSK_IS_RENDER_NODE
        if (width <= 0 || height <= 0) {
            return;
        }

        // Вызываем базовую отрисовку, которая внутри себя уже безопасно 
        // пойдет по цепочке в snapshot_line
        base.snapshot (snapshot);
    }

    public override void snapshot_line (Gtk.Snapshot snapshot, GtkSource.GutterLines lines, uint line) {
        // 1. Извлекаем реальный номер строки в текстовом буфере
        int current_line = (int) line;

        // Запрашиваем структуру блоков (пока демо-заглушки)
        bool is_block_start = this.check_if_block_starts (current_line);
        if (!is_block_start && !this.check_if_inside_foldable_block (current_line)) {
            return; 
        }

        // 2. Проверяем, свернута ли текущая строка
        bool is_collapsed = this.is_line_collapsed_by_number (current_line);

        // 3. ПОЛУЧЕНИЕ ГЕОМЕТРИИ (Решает проблему get_bounds)
        // В GtkSourceView 5 метод lines.get_line_yrange возвращает Y-координату и высоту ячейки
        int cell_y, cell_height;
        lines.get_line_yrange (line, GtkSource.GutterRendererAlignmentMode.CELL, out cell_y, out cell_height);

        if (cell_height <= 0) {
            return;
        }

        // Границы отрисовки для Cairo
        var bounds = Graphene.Rect ();
        bounds.init (0.0f, (float) cell_y, (float) current_icon_size, (float) cell_height);

        // 4. Инициализация Cairo контекста (теперь без конфликтов get_bounds)
        var cr = snapshot.append_cairo (bounds);
        cr.set_line_width (1.0);
        cr.set_source_rgba (0.5, 0.5, 0.5, 0.6);

        double mid_x = current_icon_size / 2.0f; // Центр панели
        double mid_y = cell_y + (cell_height / 2.0);

        if (is_block_start) {
            if (is_collapsed) {
                this.draw_plus_icon (cr, mid_x, mid_y);
            } else {
                this.draw_minus_icon (cr, mid_x, mid_y);
                // Направляющая линия вниз до конца текущей строки-заголовка
                cr.move_to (mid_x, mid_y + 5);
                cr.line_to (mid_x, cell_y + cell_height);
                cr.stroke ();
            }
        } else {
            // Транзитная вертикальная линия внутри развернутого блока
            cr.move_to (mid_x, cell_y);
            cr.line_to (mid_x, cell_y + cell_height);
            cr.stroke ();
        }
    }

    public override void activate (Gtk.TextIter iter, Gdk.Rectangle area, uint button, Gdk.ModifierType state, int n_presses) {
        if (button != 1 || n_presses != 1) return;

        int clicked_line = iter.get_line ();
        var view = this.get_view ();
        var buffer = view.get_buffer ();

        int start_line, end_line;
        if (!this.get_block_bounds (clicked_line, out start_line, out end_line)) {
            return; 
        }

        // ИДЕАЛЬНЫЕ ГРАНИЦЫ ДЛЯ GTK 4:
        // Начало скрытия: первый символ первой строки тела блока (start_line + 1)
        Gtk.TextIter fold_start;
        buffer.get_iter_at_line (out fold_start, start_line + 1);

        // Конец скрытия: первый символ строки, ИДУЩЕЙ ЗА БЛОКОМ (end_line + 1)
        // Это гарантирует, что \n строки end_line спрячется, и пустая строка исчезнет!
        Gtk.TextIter fold_end;
        buffer.get_iter_at_line (out fold_end, end_line + 1);

        if (fold_end.is_end()) {
            buffer.get_end_iter (out fold_end);
        }

        var tag_table = buffer.get_tag_table ();
        var invisible_tag = tag_table.lookup (this.folding_tag_name);
        if (invisible_tag == null) return;

        if (fold_start.has_tag (invisible_tag)) {
            buffer.remove_tag (invisible_tag, fold_start, fold_end);
        } else {
            buffer.apply_tag (invisible_tag, fold_start, fold_end);
        }

        // ХОТФИКС ДЛЯ НУМЕРАТОРА СТРОК (Важнейший шаг в GTK 4):
        // Просто вызвать queue_draw() для View недостаточно. Нумератор строк использует кэш макета.
        // Пересчет разметки (GtkTextLayout) форсируется через временное уведомление об изменении размера.
        view.queue_resize (); 
        this.queue_draw ();
    }

    private bool is_line_collapsed_by_number (int line_num) {
        var buffer = this.get_view ().get_buffer ();
        
        // Блок свернут, если его первая внутренняя строка имеет тег скрытия
        Gtk.TextIter next_line_iter;
        buffer.get_iter_at_line (out next_line_iter, line_num + 1);
        
        if (next_line_iter.is_end ()) return false;

        var invisible_tag = buffer.get_tag_table ().lookup (this.folding_tag_name);
        return invisible_tag != null && next_line_iter.has_tag (invisible_tag);
    }

    private bool check_if_block_starts (int line) {
        foreach (var block in this.file_blocks) {
            if (block.start_line == line) return true;
        }
        return false;
    }

    private bool check_if_inside_foldable_block (int line) {
        foreach (var block in this.file_blocks) {
            // Линия должна честно рисоваться на всех внутренних строках, 
            // включая последнюю строку блока (end_line)
            if (line > block.start_line && line <= block.end_line) {
                return true;
            }
        }
        return false;
    }
    
    private bool get_block_bounds (int line, out int start, out int end) {
        foreach (var block in this.file_blocks) {
            if (block.start_line == line) {
                start = block.start_line;
                end = block.end_line;
                return true;
            }
        }
        start = 0; end = 0; return false;
    }

    private void draw_plus_icon (Cairo.Context cr, double x, double y) {
        double w8 = current_icon_size / 2.0f;
        double w4 = current_icon_size / 4.0f;
        double w2 = current_icon_size / 8.0f;
        cr.rectangle (x - w4, y - w4, w8, w8); cr.stroke ();
        cr.move_to (x - w2, y); cr.line_to (x + w2, y); cr.stroke ();
        cr.move_to (x, y - w2); cr.line_to (x, y + w2); cr.stroke ();
    }

    private void draw_minus_icon (Cairo.Context cr, double x, double y) {
        double w8 = current_icon_size / 2.0f;
        double w4 = current_icon_size / 4.0f;
        double w2 = current_icon_size / 8.0f;
        cr.rectangle (x - w4, y - w4, w8, w8); cr.stroke ();
        cr.move_to (x - w2, y); cr.line_to (x + w2, y); cr.stroke ();
    }
}
