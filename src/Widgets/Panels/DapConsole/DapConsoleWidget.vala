/*
*/
public class Iide.DapConsoleWidget : Gtk.Box {
    private Gtk.TextView output_view;
    private Gtk.TextBuffer buffer;
    private Gtk.Entry input_entry;
    private Gtk.ScrolledWindow scroll_window;

    public DapConsoleWidget () {
        Object (orientation: Gtk.Orientation.VERTICAL, spacing: 4);
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
        var dap_service = DapService.get_instance ();
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
    }

    /**
     * АВТОМАТИЧЕСКАЯ ДОПИСЬ СЕТЕВЫХ СТРИМОВ В КОНСОЛЬ
     */
    public void append_output (string category, string text) {
        Gtk.TextIter end_iter;
        this.buffer.get_end_iter (out end_iter);
        
        // Вставляем текст с применением нужного цветового тега
        this.buffer.insert_with_tags_by_name (ref end_iter, text, -1, category);

        // Автоматически прокручиваем консоль вниз, чтобы пользователь всегда видел свежий вывод
        var adj = this.scroll_window.get_vadjustment ();
        adj.set_value (adj.get_upper() - adj.get_page_size());
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

        var dap_service = DapService.get_instance ();
        if (dap_service.current_client == null) return;

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
}
