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

    private bool is_pointer_inside = false; // Наведена ли мышь на гутер вообще
    private int hover_line = -1;            // Номер строки, над которой сейчас курсор

    public TreeSitterFoldingGutter () {
        Object ();
        this.file_blocks = new Gee.ArrayList<IndentBlock?> ();
        this.set_alignment_mode (GtkSource.GutterRendererAlignmentMode.CELL);

        // Включаем интерактивность, чтобы ловить события
        this.query_activatable.connect ((iter, area) => { return true; }); 
    }

    // ВАЖНО: В GtkSourceView 5 используем change_view вместо realized
    protected override void change_view (GtkSource.View? old_view) {
        base.change_view (old_view);

        var view = this.get_view ();
        
        // Если view == null, значит рендерер удаляют из виджета
        if (view == null) return;

        // Инициализируем контроллер движений мыши прямо на самом виджете TextView
        var motion_controller = new Gtk.EventControllerMotion ();
        
        motion_controller.enter.connect ((x, y) => {
            this.is_pointer_inside = true;
            this.update_hover_position (x, y);
        });

        motion_controller.motion.connect ((x, y) => {
            this.update_hover_position (x, y);
        });

        motion_controller.leave.connect (() => {
            this.is_pointer_inside = false;
            this.hover_line = -1;
            this.queue_draw (); // Скрываем маркеры [-] при уходе мыши
        });

        // Добавляем контроллер событий на физический виджет текстового поля
        view.add_controller (motion_controller);
    }

    private void update_hover_position (double x, double y) {
        var view = this.get_view ();
        Gtk.TextIter iter;
        
        // Переводим Y-координату мыши из координат гутера во внутренние координаты строк
        int buffer_y;
        view.window_to_buffer_coords (Gtk.TextWindowType.TEXT, 0, (int) y, null, out buffer_y);
        view.get_iter_at_location (out iter, 0, buffer_y);

        int new_hover_line = iter.get_line ();
        if (this.hover_line != new_hover_line) {
            this.hover_line = new_hover_line;
            this.queue_draw (); // Запускаем точечную перерисовку панели при движении мыши
        }
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
        // Разрешаем клик, если для строки существует хотя бы один блок
        return this.find_deepest_block_for_line (line) != null;
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

    // Вспомогательный метод для подсветки всей вертикальной линии свернутого/развернутого блока
    private bool check_if_line_belongs_to_hovered_block (int line) {
        if (this.hover_line == -1) return false;

        // Находим минимальный блок, над которым сейчас находится курсор мыши
        var hovered_block = this.find_deepest_block_for_line (this.hover_line);
        if (hovered_block == null) return false;

        // Вместо поиска одного глубокого блока для текущей строки, мы проверяем:
        // входит ли текущая отрисовываемая строка в диапазон блока, подсвеченного мышью?
        if (line >= hovered_block.start_line && line <= hovered_block.end_line) {
            
            // Дополнительная полировка в стиле QtCreator:
            // Если мышь наведена на глубокий вложенный блок (например, if), 
            // мы подсвечиваем ТОЛЬКО его (линии внешних функций не загораются синим).
            // Для этого проверяем, совпадает ли минимальный блок текущей строки с блоком мыши,
            // ИЛИ текущая строка является заголовком/хвостом, который ведет к этому блоку.
            var current_deepest = this.find_deepest_block_for_line (line);
            if (current_deepest != null && current_deepest.indent_level > hovered_block.indent_level) {
                // Если текущая строка ушла еще глубже во вложенность, чем курсор мыши,
                // внешнюю линию hovered_block мы все равно продолжаем подсвечивать синим,
                // чтобы она не разрывалась!
                return true;
            }
            
            return true;
        }

        return false;
    }

    private Iide.IndentBlock? find_deepest_block_for_line (int line) {
        Iide.IndentBlock? deepest_block = null;
        int max_indent = -1;

        foreach (var block in this.file_blocks) {
            // Проверяем, входит ли строка в диапазон блока
            if (line >= block.start_line && line <= block.end_line) {
                // Ищем блок с наибольшим уровнем вложенности
                if (block.indent_level > max_indent) {
                    max_indent = block.indent_level;
                    deepest_block = block;
                }
            }
        }
        return deepest_block;
    }

    public override void snapshot_line (Gtk.Snapshot snapshot, GtkSource.GutterLines lines, uint line) {
        // 1. ИСПРАВЛЕНИЕ: Извлекаем итератор текущего визуального ряда
        Gtk.TextIter current_line_iter;
        lines.get_iter_at_line (out current_line_iter, line);

        // 2. Получаем честный номер строки в документе (0-indexed)
        int current_line = current_line_iter.get_line ();

        // Проверяем структуру блоков Tree-sitter по честному номеру строки
        bool is_block_start = this.check_if_block_starts (current_line);
        bool is_inside_block = this.check_if_inside_foldable_block (current_line);

        if (!is_block_start && !is_inside_block) return;

        // 2. Проверяем, свернута ли текущая строка
        bool is_collapsed = this.is_line_collapsed_by_number (current_line);

        // 3. ПОЛУЧЕНИЕ ГЕОМЕТРИИ И МАСШТАБА
        int cell_y, cell_height;
        lines.get_line_yrange (line, GtkSource.GutterRendererAlignmentMode.CELL, out cell_y, out cell_height);

        if (cell_height <= 0) {
            return;
        }

        // Границы отрисовки для Cairo с учетом масштабируемого размера иконки
        var bounds = Graphene.Rect ();
        bounds.init (0.0f, (float) cell_y, (float) current_icon_size, (float) cell_height);

        // 4. Инициализация Cairo контекста
        var cr = snapshot.append_cairo (bounds);
        cr.set_line_width (1.0);

        // ВЫЧИСЛЕНИЕ ДИНАМИЧЕСКОГО ЦВЕТА (QtCreator Scope Highlight)
        bool is_current_scope_hovered = this.check_if_line_belongs_to_hovered_block (current_line);
        if (is_current_scope_hovered) {
            cr.set_source_rgba (0.2, 0.6, 1.0, 0.9); // Подсвеченный синий для активного scope
        } else {
            cr.set_source_rgba (0.5, 0.5, 0.5, 0.4); // Полупрозрачный серый по умолчанию
        }

        // Динамический расчёт центра и пропорций иконки для draw_plus/minus
        double mid_x = current_icon_size / 2.0; 
        double mid_y = cell_y + (cell_height / 2.0);
        double r = double.max (3.0, current_icon_size / 4.0); // Радиус/полуразмер квадрата иконки

        if (is_block_start) {
            if (is_collapsed) {
                // В стиле QtCreator: [+] виден ВСЕГДА
                this.draw_plus_icon_scaled (cr, mid_x, mid_y, r);
            } else {
                // В стиле QtCreator: [-] виден ТОЛЬКО когда мышь находится над панелью гутера
                if (this.is_pointer_inside) {
                    this.draw_minus_icon_scaled (cr, mid_x, mid_y, r);
                }
                // Направляющая линия вниз от центра иконки до конца текущего ряда
                cr.move_to (mid_x, mid_y + r + 1.0);
                cr.line_to (mid_x, cell_y + cell_height);
                cr.stroke ();
            }
        } else if (is_inside_block && !is_collapsed) {
            // Транзитная вертикальная линия внутри развернутого блока кода
            cr.move_to (mid_x, cell_y);
            cr.line_to (mid_x, cell_y + cell_height);
            cr.stroke ();
        }
    }

    // Масштабируемые методы отрисовки (замените ваши draw_plus/minus или адаптируйте их под параметр r)
    private void draw_plus_icon_scaled (Cairo.Context cr, double x, double y, double r) {
        cr.rectangle (x - r, y - r, r * 2, r * 2); cr.stroke ();
        cr.move_to (x - (r - 2.0), y); cr.line_to (x + (r - 2.0), y); cr.stroke ();
        cr.move_to (x, y - (r - 2.0)); cr.line_to (x, y + (r - 2.0)); cr.stroke ();
    }

    private void draw_minus_icon_scaled (Cairo.Context cr, double x, double y, double r) {
        cr.rectangle (x - r, y - r, r * 2, r * 2); cr.stroke ();
        cr.move_to (x - (r - 2.0), y); cr.line_to (x + (r - 2.0), y); cr.stroke ();
    }

    public override void activate (Gtk.TextIter iter, Gdk.Rectangle area, uint button, Gdk.ModifierType state, int n_presses) {
        if (button != 1 || n_presses != 1) return;

        int clicked_line = iter.get_line ();
        var view = this.get_view ();
        var buffer = view.get_buffer ();

        // Находим самый глубокий блок для строки клика
        var target_block = this.find_deepest_block_for_line (clicked_line);
        if (target_block == null) return;

        int start_line = target_block.start_line;
        int end_line = target_block.end_line;

        // ТОЧНЫЕ ГРАНИЦЫ ДЛЯ ИСКЛЮЧЕНИЯ ПУСТЫХ СТРОК:
        // 1. НАЧАЛО: индекс 0 строки start_line + 1
        Gtk.TextIter fold_start;
        buffer.get_iter_at_line (out fold_start, start_line + 1);

        // 2. КОНЕЦ: индекс 0 строки end_line + 1 (захватываем финальный \n строки end_line)
        Gtk.TextIter fold_end;
        buffer.get_iter_at_line (out fold_end, end_line + 1);

        // Защита: если блок упирается в самый конец файла
        if (fold_end.is_end()) {
            buffer.get_end_iter (out fold_end);
        }

        var tag_table = buffer.get_tag_table ();
        var invisible_tag = tag_table.lookup (this.folding_tag_name);
        if (invisible_tag == null) return;

        // Проверяем состояние по первой скрытой строке (fold_start)
        if (fold_start.has_tag (invisible_tag)) {
            buffer.remove_tag (invisible_tag, fold_start, fold_end);
        } else {
            buffer.apply_tag (invisible_tag, fold_start, fold_end);
        }

        view.queue_resize ();
        this.queue_draw ();
    }

    // Проверяет, является ли строка началом какого-либо синтаксического блока
    private bool check_if_block_starts (int line) {
        foreach (var block in this.file_blocks) {
            if (block.start_line == line) return true;
        }
        return false;
    }

    // Проверяет, находится ли строка внутри тела какого-либо развернутого блока
    private bool check_if_inside_foldable_block (int line) {
        var block = this.find_deepest_block_for_line (line);
        // Строка внутри тела, если она больше начала и меньше или равна концу блока
        return block != null && line > block.start_line && line <= block.end_line;
    }

    // Проверяет, свернут ли конкретный блок по номеру его начальной строки
    private bool is_line_collapsed_by_number (int line_num) {
        var buffer = this.get_view ().get_buffer ();
        
        Gtk.TextIter next_line_iter;
        buffer.get_iter_at_line (out next_line_iter, line_num + 1);
        
        if (next_line_iter.is_end ()) return false;

        var invisible_tag = buffer.get_tag_table ().lookup (this.folding_tag_name);
        return invisible_tag != null && next_line_iter.has_tag (invisible_tag);
    }
}
