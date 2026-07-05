/*
*/
public class Iide.TargetLinkPayload : GLib.Object {
    public string file_path;
    public int line;
    public TargetLinkPayload (string path, int line) {
        this.file_path = path;
        this.line = line;
    }
}

public class Iide.DapConsoleWidget : Gtk.Box {
    private weak Window window;
    private Gtk.TextView output_view;
    private Gtk.TextBuffer buffer;
    private Gtk.Entry input_entry;
    private Gtk.ScrolledWindow scroll_window;

    private Gtk.EventControllerMotion motion_controller;
    private Gtk.GestureClick click_gesture;

    public DapConsoleWidget (Window window) {
        Object (orientation: Gtk.Orientation.VERTICAL, spacing: 4);
        this.window = window;
        this.margin_start = 6; this.margin_end = 6; this.margin_top = 4; this.margin_bottom = 6;

        // 1. Буфер вывода с тегами стилизации цветов
        this.buffer = new Gtk.TextBuffer (null);
        this.create_color_tags ();

        this.output_view = new Gtk.TextView.with_buffer (this.buffer);
        this.output_view.editable = false;
        this.output_view.cursor_visible = false;
        this.output_view.wrap_mode = Gtk.WrapMode.WORD_CHAR;
        this.output_view.monospace = true;

        this.scroll_window = new Gtk.ScrolledWindow ();
        this.scroll_window.set_child (this.output_view);
        this.scroll_window.vexpand = true;
        this.append (this.scroll_window);

        // 2. Интерактивная строка ввода REPL-выражений [INDEX]
        this.input_entry = new Gtk.Entry ();
        this.input_entry.placeholder_text = "Type expression to evaluate (e.g. x + 1) and press Enter...";
        this.input_entry.activate.connect (this.on_input_submitted);
        this.append (this.input_entry);

        // ПОДКЛЮЧАЕМСЯ К СИГHАЛАМ БЭКЕНДА
        var dap_service = this.window.dap_service;
        dap_service.console_output_append.connect (this.append_output);
        
        // Слушаем смену состояний, чтобы блокировать ввод, если отладчик выключен
        dap_service.session_state_changed.connect ((state, old_state) => {
            this.input_entry.sensitive = (state != DapSessionState.EMPTY);
            if (state == DapSessionState.STARTED && old_state == DapSessionState.EMPTY) {
                this.buffer.set_text ("", 0); 
                this.append_output ("console", "--- New Debug Session Started ---\n");
            }
        });
        this.input_entry.sensitive = (dap_service.session_state != DapSessionState.EMPTY);
        
        // Включаем поддержку событий мыши для TextView
        this.motion_controller = new Gtk.EventControllerMotion ();
        this.motion_controller.motion.connect (this.on_mouse_moved_over_console);
        this.output_view.add_controller (this.motion_controller);

        // Включаем жест клика мыши
        this.click_gesture = new Gtk.GestureClick ();
        this.click_gesture.set_button (1); // Левая кнопка мыши
        this.click_gesture.pressed.connect (this.on_console_clicked);
        this.output_view.add_controller (this.click_gesture);
    }

    /**
        * Инициализация цветовой палитры для разных типов вывода
        */
    private void create_color_tags () {
        var tag_table = this.buffer.get_tag_table ();

        var stdout_tag = new Gtk.TextTag ("stdout");
        stdout_tag.foreground = "#ffffff"; // Белый обычный принт
        tag_table.add (stdout_tag);

        var stderr_tag = new Gtk.TextTag ("stderr");
        stderr_tag.foreground = "#f66151"; // Ярко-красный для трейсбеков Python
        tag_table.add (stderr_tag);

        var console_tag = new Gtk.TextTag ("console");
        console_tag.foreground = "#62a0ea"; // Синий для системных сообщений IDE/DAP
        tag_table.add (console_tag);

        var eval_in_tag = new Gtk.TextTag ("eval_in");
        eval_in_tag.foreground = "#9a9996"; // Серый цвет для эха ввода пользователя
        tag_table.add (eval_in_tag);

        var eval_out_tag = new Gtk.TextTag ("eval_out");
        eval_out_tag.foreground = "#8ff0a4"; // Приятный зеленый цвет ответа REPL
        tag_table.add (eval_out_tag);

        // ТЕГ ДЛЯ ГИПЕРССЫЛОК ФАЙЛОВ
        var link_tag = new Gtk.TextTag ("link");
        link_tag.underline = Pango.Underline.SINGLE; // Делаем ссылку подчеркнутой
        link_tag.foreground = "#3584e4";             // Приятный синий цвет Adwaita для ссылок
        
        // Сохраняем в объект тега метаданные (чтобы отличать его от других тегов)
        link_tag.set_data ("is_link", true);
        tag_table.add (link_tag);
    }

    /**
     * УМНЫЙ АВТОМАТИЧЕСКИЙ ПУШ С ПОИСКОМ ФАЙЛОВЫХ ССЫЛОК
     */
    public void append_output (string category, string text) {
        Gtk.TextIter end_iter;
        this.buffer.get_end_iter (out end_iter);

        if (category != "stdout" && category != "stderr") {
            this.buffer.insert_with_tags_by_name (ref end_iter, text, -1, category);
            this.scroll_to_bottom ();
            return;
        }

        // 1. Собираем массив паттернов из активного адаптера
        var dap_service = this.window.dap_service;
        string[] active_patterns = {};

        if (dap_service.current_client != null) {
            var config = dap_service.current_client.get_config ();
            if (config.output_link_regex_patterns.length > 0) {
                active_patterns = config.output_link_regex_patterns;
            }
        }

        // 2. Компилируем Си-объекты GLib.Regex
        var active_regexes = new Gee.ArrayList<GLib.Regex> ();
        foreach (var pattern in active_patterns) {
            try {
                active_regexes.add (new GLib.Regex (pattern));
            } catch (GLib.Error e) {
                LoggerService.get_instance ().error ("DAP-UI", "Invalid regex pattern in manifest: " + pattern);
            }
        }

        // 3. ПОСЛЕДОВАТЕЛЬНЫЙ ДЕКЛАРАТИВНЫЙ ПОИСК ССЫЛОК ПО ВСЕМ РЕГУЛЯРКАМ
        // Чтобы регулярки не конфликтовали внутри одной строки, мы ищем совпадения по очереди.
        int last_pos = 0;
        
        // Карта для предотвращения наложения тегов: [старт_индекс] -> [TargetLinkPayload]
        var found_matches = new Gee.HashMap<int, TargetLinkPayload> ();
        var match_lengths = new Gee.HashMap<int, int> ();

        foreach (var regex in active_regexes) {
            try {
                GLib.MatchInfo match_info;
                if (regex.match (text, 0, out match_info)) {
                    while (match_info.matches ()) {
                        int start_pos, end_pos;
                        match_info.fetch_pos (0, out start_pos, out end_pos);

                        // Проверяем контракт: Группа 1 — путь, Группа 2 — строка
                        string? file_path = match_info.fetch (1);
                        string? line_num_str = match_info.fetch (2);

                        if (file_path != null && file_path != "" && line_num_str != null && line_num_str != "") {
                            // Сохраняем совпадение в промежуточную мапу
                            var payload = new TargetLinkPayload (file_path, int.parse (line_num_str));
                            found_matches.set (start_pos, payload);
                            match_lengths.set (start_pos, end_pos - start_pos);
                        }
                        match_info.next ();
                    }
                }
            } catch (GLib.RegexError err) {}
        }

        // 4. ФИЗИЧЕСКИЙ РЕНДЕРИНГ ИЗ МЕЖДУТOЧНOЙ МАПЫ
        // Перебираем индексы строки от 0 до конца
        while (last_pos < text.length) {
            if (found_matches.has_key (last_pos)) {
                var payload = found_matches.get (last_pos);
                int len = match_lengths.get (last_pos);
                string full_match_text = text.substring (last_pos, len);

                // Вставляем ссылку!
                this.buffer.get_end_iter (out end_iter);
                Gtk.TextMark start_mark = this.buffer.create_mark (null, end_iter, true);
                this.buffer.insert_with_tags_by_name (ref end_iter, full_match_text, -1, "link");
                
                start_mark.set_data<TargetLinkPayload> ("payload", payload);
                last_pos += len;
            } else {
                // Печатаем посимвольно или до следующего совпадения
                this.buffer.get_end_iter (out end_iter);
                this.buffer.insert_with_tags_by_name (ref end_iter, text.substring (last_pos, 1), -1, category);
                last_pos++;
            }
        }

        this.scroll_to_bottom ();
    }

    private void scroll_to_bottom () {
        var adj = this.scroll_window.get_vadjustment ();
        adj.set_value (adj.get_upper () - adj.get_page_size ());
    }

    /**
     * ОТПРАВКА ВВЕДЕННОГО ВЫРАЖЕНИЯ ПО СЕТИ НА ВЫЧИСЛЕНИЕ (Enter)
     */
    private void on_input_submitted () {
        string expr = this.input_entry.text.strip ();
        if (expr == "") return;

        this.input_entry.text = ""; // Очищаем строку ввода

        // 1. Печатаем в консоль эхо ввода пользователя в стиле терминала: `>>> my_var`
        this.append_output ("eval_in", ">>> " + expr + "\n");

        var dap_service = this.window.dap_service;
        if (dap_service.current_client == null)
            return;

        // Определяем текущий кадр стека (если мы на паузе, передаем его, если код бежит — null)
        int frame_id = (dap_service.session_state == DapSessionState.BREAKPOINT) ? 
            dap_service.current_frame_id : -1;

        // Запускаем асинхронный RPC-запрос вычисления в режиме fire-and-forget
        dap_service.current_client.request_evaluate.begin (expr, frame_id, (obj, res) => {
            try {
                string? result = dap_service.current_client.request_evaluate.end (res);
                
                // Возвращаемся в UI-поток для безопасной печати ответа
                Idle.add (() => {
                    if (result != null) {
                        // Печатаем результат вычисления зеленым цветом!
                        this.append_output ("eval_out", " = " + result + "\n");
                    }
                    return Source.REMOVE;
                });
            } catch (GLib.Error err) {
                string err_msg = err.message;
                Idle.add (() => {
                    this.append_output ("stderr", "Evaluation failed: " + err_msg + "\n");
                    return Source.REMOVE;
                });
            }
        });
    }

    private void on_mouse_moved_over_console (double x, double y) {
        // 1. Переводим пиксельные координаты виджета в координаты разметки TextIter буфера GTK
        int buffer_x, buffer_y;
        this.output_view.window_to_buffer_coords (
            Gtk.TextWindowType.TEXT,
            (int) x,
            (int) y,
            out buffer_x,
            out buffer_y
        );

        Gtk.TextIter iter;
        this.output_view.get_iter_at_location (out iter, buffer_x, buffer_y);

        // ===================================================================
        // СОВРЕМЕННЫЙ GTK4 КАНOН ПРОВЕРКИ МОДИФИКАТOРОВ КЛАВИАТУРЫ
        // Мы достаем битовую маску зажатых клавиш прямо из нашего контроллера!
        // ===================================================================
        Gdk.ModifierType modifiers = this.motion_controller.get_current_event_state ();
        bool ctrl_pressed = (modifiers & Gdk.ModifierType.CONTROL_MASK) != 0;

        // Проверяем, висит ли на этой букве тег "link"
        bool is_over_link = iter.has_tag (this.buffer.get_tag_table ().lookup ("link"));

        // Если мы над ссылкой И зажат Ctrl — включаем иконку кликабельной руки!
        if (is_over_link && ctrl_pressed) {
            this.output_view.set_cursor_from_name ("pointer");
        } else {
            this.output_view.set_cursor_from_name ("text");
        }
    }

    private void on_console_clicked (int n_press, double x, double y) {
        // Извлекаем модификаторы клавиш из текущего системного события GTK4
        var current_event = this.click_gesture.get_current_event ();
        if (current_event == null) return;

        Gdk.ModifierType modifiers = current_event.get_modifier_state ();
        bool ctrl_pressed = (modifiers & Gdk.ModifierType.CONTROL_MASK) != 0;

        // Если Ctrl не зажат — это обычный клик пользователя для выделения текста, выходим
        if (!ctrl_pressed) return;

        int buffer_x, buffer_y;
        this.output_view.window_to_buffer_coords (
            Gtk.TextWindowType.TEXT, 
            (int) x, 
            (int) y, 
            out buffer_x, 
            out buffer_y
        );

        Gtk.TextIter iter;
        this.output_view.get_iter_at_location (out iter, buffer_x, buffer_y);

        var link_tag = this.buffer.get_tag_table ().lookup ("link");
        if (iter.has_tag (link_tag)) {
            // Вытаскиваем список всех маркеров на этой позиции, чтобы найти наш payload
            Gtk.TextIter start_search = iter;
            start_search.backward_to_tag_toggle (link_tag);
            
            // Ищем маркер, в который мы бережно сохранили данные пути в методе append_output
            Gtk.TextMark? found_mark = null;
            Gtk.TextIter search_iter = start_search;
            
            while (search_iter.compare (iter) <= 0) {
                var marks = search_iter.get_marks ();
                foreach (var m in marks) {
                    if (m.get_data<TargetLinkPayload> ("payload") != null) {
                        found_mark = m;
                        break;
                    }
                }
                if (found_mark != null) break;
                if (!search_iter.forward_char ()) break;
            }

            if (found_mark != null) {
                var payload = found_mark.get_data<TargetLinkPayload> ("payload");
                if (payload != null) {
                    // Конвертируем системный путь Linux в канонический URI для нашей IDE
                    var file_obj = GLib.File.new_for_path (payload.file_path);
                    string file_uri = file_obj.get_uri ();

                    LoggerService.get_instance ().info ("DAP-UI", @"[Ctrl+Click] Navigating to $file_uri line $(payload.line)");

                    // МГНОВЕННЫЙ ПРЫЖОК: Командуем UI открыть файл и подсветить строку!
                    // Так как в Python трейсбеках строки 1-based, переводим в 0-indexed для GTK (делаем -1)
                    Idle.add (() => {
                        this.window.document_manager.open_document_with_selection (file_obj, payload.line - 1, 0, 0, null);
                        return Source.REMOVE;
                    });
                }
            }
        }
    }
}
