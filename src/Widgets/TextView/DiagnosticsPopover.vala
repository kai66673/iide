public class Iide.DiagnosticsPopover : Gtk.Popover {
    private Gtk.ListBox list_box;
    private GtkSource.View text_view;

    public DiagnosticsPopover (Gtk.Widget parent, GtkSource.View view) {
        this.set_parent (parent);
        this.text_view = view;

        // Настройка внешнего вида
        this.set_position (Gtk.PositionType.TOP); // Попап будет расти вверх от статус-бара
        this.set_has_arrow (true);
        this.set_autohide (true);

        var scroll = new Gtk.ScrolledWindow () {
            max_content_height = 400,
            propagate_natural_height = true,
            width_request = 400
        };

        list_box = new Gtk.ListBox ();
        list_box.add_css_class ("boxed-list");
        list_box.set_selection_mode (Gtk.SelectionMode.NONE); // Нам не нужно выделение, только клик

        scroll.set_child (list_box);
        this.set_child (scroll);

        list_box.row_activated.connect ((row) => {
            var diag_row = row as Adw.ActionRow;
            if (diag_row != null) {
                // Достаем данные и выполняем переход (см. ниже)
                Gtk.TextIter start_line, end_line;

                // 1. Получаем итератор позиции ошибки из марки
                var buffer = (GtkSource.Buffer) text_view.buffer;
                var mark = diag_row.get_data<LspDiagnosticsMark> ("mark");
                if (mark == null) {
                    return;
                }
                buffer.get_iter_at_mark (out start_line, mark);

                // 2. Устанавливаем итератор на начало строки
                start_line.set_line_offset (0);

                // 3. Создаем второй итератор и переводим его в конец этой же строки
                end_line = start_line;
                if (!end_line.ends_line ()) {
                    end_line.forward_to_line_end ();
                }

                // 4. Устанавливаем выделение на всю строку
                // В GTK select_range(курсор, граница) выделит всё между ними
                buffer.select_range (start_line, end_line);

                // 5. Прокрутка и фокус
                text_view.scroll_to_iter (start_line, 0.1, false, 0, 0.5);
                text_view.grab_focus ();

                // Закрываем попап
                this.popdown ();
            }
        });
    }

    public void refresh () {
        // 1. Очистка старого содержимого
        Gtk.Widget? child;
        while ((child = list_box.get_first_child ()) != null) {
            list_box.remove (child);
        }

        var buffer = (GtkSource.Buffer) text_view.buffer;
        bool found_any = false;

        // 2. Твой алгоритм прохода по строкам
        int line_count = buffer.get_line_count ();
        for (int i = 0; i < line_count; i++) {
            Gtk.TextIter iter;
            buffer.get_iter_at_line (out iter, i);

            var iter_marks = iter.get_marks ();

            // Если на этой позиции вообще есть марки
            if (iter_marks != null) {
                foreach (var m in iter_marks) {
                    if (m is LspDiagnosticsMark) {
                        add_diagnostic_row ((LspDiagnosticsMark) m);
                        found_any = true;
                    }
                }
            }
        }

        // 3. Обработка случая "Всё чисто"
        if (!found_any) {
            var status_page = new Adw.StatusPage () {
                title = "No issues found",
                icon_name = "emblem-ok-symbolic",
                description = "LSP servers haven't reported any problems."
            };
            status_page.add_css_class ("compact"); // Если используешь libadwaita 1.2+
            list_box.append (status_page);
        }
    }

    private void add_diagnostic_row (LspDiagnosticsMark mark) {
        Gtk.TextIter iter;
        var buffer = (GtkSource.Buffer) text_view.buffer;
        buffer.get_iter_at_mark (out iter, mark);
        int line = iter.get_line () + 1;

        var row = new Adw.ActionRow () {
            title = mark.diagnostic_message,
            subtitle = @"Line $line",
            activatable = true, // ОБЯЗАТЕЛЬНО
            selectable = false
        };
        row.set_data ("mark", mark);

        // Добавляем иконку в начало (префикс)
        var icon_name = mark.get_icon_name ();
        if (icon_name != null) {
            var img = new Gtk.Image.from_icon_name (icon_name + "-symbolic");
            img.add_css_class (mark.category); // Можно покрасить иконку через CSS
            row.add_prefix (img);
        }

        // При клике на строку — прыгаем к марке
        row.activated.connect (() => {
            Gtk.TextIter start_line, end_line;

            // 1. Получаем итератор позиции ошибки из марки
            buffer.get_iter_at_mark (out start_line, mark);

            // 2. Устанавливаем итератор на начало строки
            start_line.set_line_offset (0);

            // 3. Создаем второй итератор и переводим его в конец этой же строки
            end_line = start_line;
            if (!end_line.ends_line ()) {
                end_line.forward_to_line_end ();
            }

            // 4. Устанавливаем выделение на всю строку
            // В GTK select_range(курсор, граница) выделит всё между ними
            buffer.select_range (start_line, end_line);

            // 5. Прокрутка и фокус
            text_view.scroll_to_iter (start_line, 0.1, false, 0, 0.5);
            text_view.grab_focus ();

            // Закрываем попап
            this.popdown ();
        });

        list_box.append (row);
    }
}
