/*
*/
using Gtk;
using GtkSource;
using Cairo;

namespace Iide {

    // Класс-обертка для хранения свернутых диапазонов на базе плавающих маркеров
    public class FoldedMarkRange : GLib.Object {
        public Gtk.TextMark start_mark;
        public Gtk.TextMark end_mark;

        public FoldedMarkRange (Gtk.TextBuffer buffer, Gtk.TextIter start, Gtk.TextIter end) {
            Object ();
            // left_gravity = true заставляет маркеры автоматически сдвигаться 
            // вместе с текстом при вставках/удалениях строк выше блока
            this.start_mark = buffer.create_mark (null, start, true);
            this.end_mark = buffer.create_mark (null, end, true);
        }

        public void free_marks (Gtk.TextBuffer buffer) {
            buffer.delete_mark (this.start_mark);
            buffer.delete_mark (this.end_mark);
        }
    }

    public class TreeSitterFoldingGutter : GtkSource.GutterRenderer {
        // Динамический список реально свернутых в данный момент блоков
        public Gee.ArrayList<FoldedMarkRange> active_folds = new Gee.ArrayList<FoldedMarkRange> ();
        
        // Актуальный кэш структуры документа от Tree-sitter
        private Gee.List<Iide.IndentBlock?> file_blocks;
        
        private string folding_tag_name = "$FOLD_HIDE";
        private int current_icon_size = 16;

        // Состояние мыши для эффектов в стиле QtCreator
        private bool is_pointer_inside = false;
        private int hover_line = -1;

        public TreeSitterFoldingGutter () {
            Object ();
            this.file_blocks = new Gee.ArrayList<Iide.IndentBlock?> ();
            this.set_alignment_mode (GtkSource.GutterRendererAlignmentMode.CELL);
        }

        // Вызывается из SourceView.vala при обновлении синтаксического дерева
        public void update_blocks_data (Gee.List<Iide.IndentBlock?> blocks) {
            this.file_blocks = blocks;
            this.queue_draw ();
        }

        // Интеграция EventController-ов для GTK 4
        protected override void change_view (GtkSource.View? old_view) {
            base.change_view (old_view);
            var view = this.get_view ();
            if (view == null) return;

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
                this.queue_draw ();
            });

            view.add_controller (motion_controller);
        }

        private void update_hover_position (double x, double y) {
            var view = this.get_view ();
            Gtk.TextIter iter;
            int buffer_y;
            view.window_to_buffer_coords (Gtk.TextWindowType.TEXT, 0, (int) y, null, out buffer_y);
            view.get_iter_at_location (out iter, 0, buffer_y);

            int new_hover_line = iter.get_line ();
            if (this.hover_line != new_hover_line) {
                this.hover_line = new_hover_line;
                this.queue_draw ();
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


        public override void measure (Gtk.Orientation orientation, int for_size, out int minimum, out int natural, out int minimum_baseline, out int natural_baseline) {
            minimum_baseline = natural_baseline = -1;
            if (orientation == Gtk.Orientation.HORIZONTAL) {
                minimum = natural = this.current_icon_size;
            } else {
                minimum = natural = 0;
            }
        }

        // ОТРИСОВКА В СТИЛЕ QtCreator (GtkSourceView 5)
        public override void snapshot_line (Gtk.Snapshot snapshot, GtkSource.GutterLines lines, uint line) {
            Gtk.TextIter current_line_iter;
            lines.get_iter_at_line (out current_line_iter, line);
            int current_line = current_line_iter.get_line ();

            bool is_block_start = this.check_if_block_starts (current_line);
            bool is_inside_block = this.check_if_inside_foldable_block (current_line);

            if (!is_block_start && !is_inside_block) return;

            bool is_collapsed = this.is_line_collapsed_by_number (current_line);

            int cell_y, cell_height;
            lines.get_line_yrange (line, GtkSource.GutterRendererAlignmentMode.CELL, out cell_y, out cell_height);
            if (cell_height <= 0) return;

            var bounds = Graphene.Rect ();
            bounds.init (0.0f, (float) cell_y, (float) this.current_icon_size, (float) cell_height);

            var cr = snapshot.append_cairo (bounds);
            cr.set_line_width (1.0);

            // Scope Подсветка минимального региона
            bool is_current_scope_hovered = this.check_if_line_belongs_to_hovered_block (current_line);
            if (is_current_scope_hovered) {
                cr.set_source_rgba (0.2, 0.6, 1.0, 0.9); // Синий
            } else {
                cr.set_source_rgba (0.5, 0.5, 0.5, 0.4); // Серый полупрозрачный
            }

            double mid_x = this.current_icon_size / 2.0; 
            double mid_y = cell_y + (cell_height / 2.0);
            double r = double.max (3.0, this.current_icon_size / 4.0);

            if (is_block_start) {
                if (is_collapsed) {
                    // [+] виден всегда
                    this.draw_plus_icon_scaled (cr, mid_x, mid_y, r);
                } else {
                    // [-] виден только при наведении мыши на панель
                    if (this.is_pointer_inside) {
                        this.draw_minus_icon_scaled (cr, mid_x, mid_y, r);
                    }
                    cr.move_to (mid_x, mid_y + r + 1.0);
                    cr.line_to (mid_x, cell_y + cell_height);
                    cr.stroke ();
                }
            } else if (is_inside_block && !is_collapsed) {
                cr.move_to (mid_x, cell_y);
                cr.line_to (mid_x, cell_y + cell_height);
                cr.stroke ();
            }
        }

        // ОБРАБОТКА КЛИКА ПО ВСЕМУ РЕГИОНУ НА БАЗЕ TEXTMARK (GTK 4)
        public override void activate (Gtk.TextIter iter, Gdk.Rectangle area, uint button, Gdk.ModifierType state, int n_presses) {
            if (button != 1 || n_presses != 1) return;

            int clicked_line = iter.get_line ();
            var view = this.get_view ();
            var buffer = view.get_buffer ();

            var target_block = this.find_deepest_block_for_line (clicked_line);
            if (target_block == null) return;

            int start_line = target_block.start_line;
            int end_line = target_block.end_line;

            // Идеальная проверенная математика границ для схлопывания без лишних пустых строк
            Gtk.TextIter fold_start;
            buffer.get_iter_at_line (out fold_start, start_line + 1);

            Gtk.TextIter fold_end;
            buffer.get_iter_at_line (out fold_end, end_line + 1);
            if (fold_end.is_end()) buffer.get_end_iter (out fold_end);

            var invisible_tag = buffer.get_tag_table ().lookup (this.folding_tag_name);
            if (invisible_tag == null) return;

            // Ищем маркер свернутости
            FoldedMarkRange? existing_fold = null;
            foreach (var fold in this.active_folds) {
                Gtk.TextIter mark_iter;
                buffer.get_iter_at_mark (out mark_iter, fold.start_mark);
                if (mark_iter.get_line () - 1 == start_line) {
                    existing_fold = fold;
                    break;
                }
            }

            if (existing_fold != null) {
                // Разворачиваем
                Gtk.TextIter s, e;
                buffer.get_iter_at_mark (out s, existing_fold.start_mark);
                buffer.get_iter_at_mark (out e, existing_fold.end_mark);
                
                buffer.remove_tag (invisible_tag, s, e);
                existing_fold.free_marks (buffer);
                this.active_folds.remove (existing_fold);
            } else {
                // Сворачиваем
                buffer.apply_tag (invisible_tag, fold_start, fold_end);
                var new_fold = new FoldedMarkRange (buffer, fold_start, fold_end);
                this.active_folds.add (new_fold);
            }

            view.queue_resize ();
            this.queue_draw ();
        }

        public override bool query_activatable (Gtk.TextIter iter, Gdk.Rectangle area) {
            int line = iter.get_line ();
            return this.find_deepest_block_for_line (line) != null;
        }

        // ВСПОМОГАТЕЛЬНЫЕ ПОИСКОВЫЕ МЕТОДЫ (ИСТОЧНИК ПРАВДЫ — ТREE-SITTER)
        
        public Iide.IndentBlock? find_deepest_block_for_line (int line) {
            Iide.IndentBlock? deepest_block = null;
            int max_indent = -1;

            foreach (var block in this.file_blocks) {
                if (line >= block.start_line && line <= block.end_line) {
                    if (block.indent_level > max_indent) {
                        max_indent = block.indent_level;
                        deepest_block = block;
                    }
                }
            }
            return deepest_block;
        }

        private bool check_if_block_starts (int line) {
            foreach (var block in this.file_blocks) {
                if (block.start_line == line) return true;
            }
            return false;
        }

        private bool check_if_inside_foldable_block (int line) {
            var block = this.find_deepest_block_for_line (line);
            return block != null && line > block.start_line && line <= block.end_line;
        }

        private bool check_if_line_belongs_to_hovered_block (int line) {
            if (this.hover_line == -1) return false;

            var hovered_block = this.find_deepest_block_for_line (this.hover_line);
            if (hovered_block == null) return false;

            var current_block = this.find_deepest_block_for_line (line);
            if (current_block == null) return false;

            if (line >= hovered_block.start_line && line <= hovered_block.end_line) {
                if (current_block.indent_level > hovered_block.indent_level) {
                    return true;
                }
                return hovered_block.start_line == current_block.start_line && 
                       hovered_block.end_line == current_block.end_line;
            }
            return false;
        }

        private bool is_line_collapsed_by_number (int line_num) {
            var buffer = this.get_view ().get_buffer ();
            foreach (var fold in this.active_folds) {
                Gtk.TextIter mark_iter;
                buffer.get_iter_at_mark (out mark_iter, fold.start_mark);
                if (mark_iter.get_line () - 1 == line_num) {
                    return true;
                }
            }
            return false;
        }

        // ОТРИСОВКА ИКОНОК CAIRO
        private void draw_plus_icon_scaled (Cairo.Context cr, double x, double y, double r) {
            cr.rectangle (x - r, y - r, r * 2, r * 2); cr.stroke ();
            cr.move_to (x - (r - 2.0), y); cr.line_to (x + (r - 2.0), y); cr.stroke ();
            cr.move_to (x, y - (r - 2.0)); cr.line_to (x, y + (r - 2.0)); cr.stroke ();
        }

        private void draw_minus_icon_scaled (Cairo.Context cr, double x, double y, double r) {
            cr.rectangle (x - r, y - r, r * 2, r * 2); cr.stroke ();
            cr.move_to (x - (r - 2.0), y); cr.line_to (x + (r - 2.0), y); cr.stroke ();
        }
    }
}
