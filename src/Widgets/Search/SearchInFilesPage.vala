public class Iide.SearchInFilesPage : Gtk.Box, SearchPanelInterface {
    private Gtk.SearchEntry search_entry;
    private SearchResultsView results_view;
    private Iide.ProjectManager project_manager;
    private string project_root_path;

    private Gtk.Stack status_stack;
    private Gtk.Spinner spinner;

    private uint debounce_id = 0;
    private bool content_loaded = false;

    private const int MAX_RESULTS = 100;

    private ThreadPool<SearchTask> thread_pool;
    private Cancellable? search_cancellable = null;
    private Gee.List<SearchResult> all_results;
    private string cache_query = "";
    private Gee.List<SearchResult> search_cache = new Gee.ArrayList<SearchResult> ();

    public void focus_search_entry () {
        search_entry.grab_focus ();
    }

    public SearchInFilesPage () {
        Object (orientation : Gtk.Orientation.VERTICAL, spacing: 0);
        this.project_manager = Iide.ProjectManager.get_instance ();
        this.all_results = new Gee.ArrayList<SearchResult> ();

        var project_root = project_manager.get_current_project_root ();
        if (project_root != null) {
            this.project_root_path = project_root.get_path () ?? "";
        } else {
            this.project_root_path = "";
        }

        setup_ui ();

        project_manager.file_cache_updated.connect (on_file_cache_updated);
        project_manager.file_cache_invalidated.connect (on_file_cache_invalidated);

        // 1. Инициализируем пул ОДИН РАЗ в конструкторе
        try {
            thread_pool = new ThreadPool<SearchTask>.with_owned_data ((task) => { this.search_files_in_task (task); },
                (int) GLib.get_num_processors (),
                false);
        } catch (ThreadError e) {
            critical ("Ошибка пула потоков: %s", e.message);
        }
    }

    ~SearchInFilesPage () {
        project_manager.file_cache_updated.disconnect (on_file_cache_updated);
        project_manager.file_cache_invalidated.disconnect (on_file_cache_invalidated);
    }

    private void setup_ui () {
        var vbox = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
        vbox.margin_top = 12;
        vbox.margin_bottom = 12;
        vbox.margin_start = 12;
        vbox.margin_end = 12;

        search_entry = new Gtk.SearchEntry () {
            placeholder_text = _("Search text..."),
            hexpand = true
        };
        vbox.append (search_entry);

        results_view = new SearchResultsView ();

        status_stack = new Gtk.Stack ();
        status_stack.transition_type = Gtk.StackTransitionType.CROSSFADE;

        var loading_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 12);
        loading_box.valign = Gtk.Align.CENTER;
        loading_box.halign = Gtk.Align.CENTER;

        spinner = new Gtk.Spinner ();
        spinner.set_size_request (32, 32);

        var loading_label = new Gtk.Label (_("Indexing project files..."));
        loading_label.add_css_class ("dim-label");

        loading_box.append (spinner);
        loading_box.append (loading_label);

        status_stack.add_named (loading_box, "loading");
        status_stack.add_named (results_view, "ready");

        vbox.append (status_stack);
        this.append (vbox);

        search_entry.changed.connect (on_search_changed);

        var key_controller = new Gtk.EventControllerKey ();
        key_controller.key_pressed.connect (on_key_pressed);
        search_entry.add_controller (key_controller);

        results_view.list_view.activate.connect (() => {
            open_selected ();
        });

        search_entry.activate.connect (() => {
            open_selected ();
        });

        search_entry.focus_on_click = false;
    }

    private bool is_text_file (string path) {
        var file = GLib.File.new_for_path (path);
        try {
            var info = file.query_info (FileAttribute.STANDARD_CONTENT_TYPE, FileQueryInfoFlags.NONE);
            string content_type = info.get_content_type ();
            return ContentType.is_a (content_type, "text/plain");
        } catch (Error e) {
            return false;
        }
    }

    private bool on_key_pressed (Gtk.EventControllerKey controller, uint keyval, uint keycode, Gdk.ModifierType modifiers) {
        if (keyval == Gdk.Key.Escape) {
            close_requested ();
            return true;
        } else if (keyval == Gdk.Key.Return || keyval == Gdk.Key.KP_Enter) {
            open_selected ((modifiers & Gdk.ModifierType.SHIFT_MASK) == 0);
            return true;
        } else if (keyval == Gdk.Key.Up || keyval == Gdk.Key.KP_Up) {
            results_view.select_up ();
            return true;
        } else if (keyval == Gdk.Key.Down || keyval == Gdk.Key.KP_Down) {
            results_view.select_down ();
            return true;
        }
        return false;
    }

    private void on_file_cache_updated () {
    }

    private void on_file_cache_invalidated () {
        all_results.clear ();
    }

    private void on_search_changed () {
        if (debounce_id > 0) {
            Source.remove (debounce_id);
            debounce_id = 0;
        }

        string query = search_entry.get_text ().strip ();

        if (query.length < 3) {
            clear_results ();
            return;
        }

        debounce_id = Timeout.add (200, () => {
            perform_search_wrapper.begin ();
            debounce_id = 0;
            return false;
        });
    }

    private async void perform_search_wrapper () {
        yield ensure_content_loaded ();
        yield perform_search_async ();
    }

    private async void ensure_content_loaded () {
        if (content_loaded) {
            return;
        }

        status_stack.visible_child_name = "loading";
        spinner.start ();

        yield project_manager.ensure_file_cache_async ();

        content_loaded = true;

        spinner.stop ();
        status_stack.visible_child_name = "ready";
    }

    private int fuzzy_match_with_positions (string text, string query, Gee.List<MatchRange> matches) {
        if (text.length == 0 || query.length == 0) {
            return 0;
        }

        var text_lower = text.down ();
        var query_lower = query.down ();

        if (text_lower.contains (query_lower)) {
            var pos = text_lower.index_of (query_lower);
            matches.add (new MatchRange (pos, pos + (int) query_lower.length));
            if (pos == 0) {
                return 1000 + (1000 - text.length);
            }
            return 500 + (1000 - pos);
        }

        int score = 0;
        int consecutive = 0;
        int last_match = -1;
        bool prev_was_sep = true;
        bool matched_all = true;
        var match_positions = new Gee.ArrayList<int> ();

        for (int qi = 0; qi < query_lower.length; qi++) {
            bool found = false;
            for (int idx = last_match + 1; idx < text_lower.length; idx++) {
                if (text_lower[idx] == query_lower[qi]) {
                    found = true;
                    match_positions.add (idx);
                    last_match = idx;
                    consecutive++;

                    if (idx == 0 || prev_was_sep) {
                        score += 150;
                    } else if (consecutive > 1) {
                        score += consecutive * 10;
                    } else {
                        score += 15;
                    }
                    break;
                } else {
                    score -= 1;
                }
            }

            if (!found) {
                matched_all = false;
                break;
            }

            unichar c = last_match >= 0 && last_match < (int) text.length ? text[last_match] : ' ';
            prev_was_sep = !c.isalnum () && c != '_';
        }

        if (!matched_all) {
            return 0;
        }

        int i = 0;
        while (i < match_positions.size) {
            int start = match_positions[i];
            int end = start + 1;

            while (i + 1 < match_positions.size && match_positions[i + 1] == match_positions[i] + 1) {
                end = match_positions[i + 1] + 1;
                i++;
            }

            matches.add (new MatchRange (start, end));
            i++;
        }

        return score;
    }

    private class SearchTask {
        public Gee.List<Iide.FileEntry> files;
        public string query;
        public Gee.List<SearchResult> results;
        public Cancellable cancellable;

        public SearchTask (Gee.List<Iide.FileEntry> files, string query, Cancellable cancellable) {
            this.files = files;
            this.query = query;
            this.results = new Gee.ArrayList<SearchResult> ();
            this.results = new Gee.ArrayList<SearchResult> ();
        }
    }

    private void clear_results () {
        all_results = new Gee.ArrayList<SearchResult> ();
        update_results ();

        // Очищаем кэш
        cache_query = "";
        search_cache = new Gee.ArrayList<SearchResult> ();
    }

    private async void perform_search_async () {
        string new_query = search_entry.get_text ().strip ();

        // Проверка на минимальную длину
        if (new_query.length < 3) {
            clear_results (); // Очистка ListView и сброс кэша
            return;
        }

        // Проверка: можем ли использовать кэш?
        // Условие: кэш не пуст И новый запрос является продолжением того, что в кэше
        bool can_use_cache = search_cache.size > 0 &&
            cache_query.length > 0 &&
            new_query.has_prefix (cache_query);

        if (can_use_cache) {
            // УТОЧНЯЮЩИЙ ПОИСК (Мгновенно)
            LoggerService.get_instance ().debug ("TEXT SEARCH", "УТОЧНЯЮЩИЙ ПОИСК: " + new_query);
            filter_cache_to_ui (new_query);
        } else {
            // ПОЛНЫЙ ПОИСК (Диск + Потоки)
            LoggerService.get_instance ().debug ("TEXT SEARCH", "ПОЛНЫЙ ПОИСК: " + new_query);
            clear_results ();
            status_stack.visible_child_name = "loading";
            spinner.start ();

            if (search_cancellable != null)search_cancellable.cancel ();
            search_cancellable = new Cancellable ();
            var current_run_cancellable = search_cancellable;

            // Выполняем тяжелую работу
            yield perform_full_disk_search_async (new_query, current_run_cancellable);
        }

        spinner.stop ();
        status_stack.set_visible_child_name ("results");
    }

    private void filter_cache_to_ui (string query) {
        var filtered_results = new Gee.ArrayList<SearchResult> ();

        foreach (var res in search_cache) {
            var matches = new Gee.ArrayList<MatchRange> ();
            // Пересчитываем score для НОВОГО (более длинного) запроса
            int score = fuzzy_match_with_positions (res.line_content, query, matches);

            // В UI пускаем только качественные совпадения
            if (score > 50) {
                filtered_results.add (new SearchResult (
                                                        res.file_path, res.relative_path,
                                                        res.line_number, res.line_content,
                                                        matches, null, score
                ));
            }
        }

        // Сортируем и отображаем топ-200
        filtered_results.sort ((a, b) => b.score - a.score);
        all_results = filtered_results;
        update_results ();
    }

    private async void perform_full_disk_search_async (string current_query, Cancellable current_run_cancellable) {
        var file_cache = project_manager.get_file_cache ();
        if (file_cache == null) {
            clear_results ();
            return;
        }

        // ВКЛЮЧАЕМ ИНДИКАТОР ЗАГРУЗКИ
        status_stack.visible_child_name = "loading";
        spinner.start ();

        var text_files = new Gee.ArrayList<Iide.FileEntry> ();
        foreach (var f in file_cache) {
            if (is_text_file (f.path)) {
                text_files.add (f);
            }
        }

        if (text_files.size == 0) {
            clear_results ();
            return;
        }

        int num_threads = (int) GLib.get_num_processors ();
        int files_per_thread = (text_files.size + num_threads - 1) / num_threads;
        var tasks = new Gee.ArrayList<SearchTask> ();

        // 1. Раздаем задачи пулу
        for (int t = 0; t < num_threads; t++) {
            int start = t * files_per_thread;
            int end = int.min (start + files_per_thread, text_files.size);
            if (start >= text_files.size)break;

            var task = new SearchTask (text_files.slice (start, end), current_query, current_run_cancellable);
            tasks.add (task);

            try {
                thread_pool.add (task);
            } catch (ThreadError e) { /* handle error */ }
        }

        // 2. Вместо thread.join() — асинхронное ожидание
        // Мы будем проверять пул в цикле, не блокируя UI
        while (thread_pool.get_num_threads () > 0 || thread_pool.unprocessed () > 0) {
            if (current_run_cancellable.is_cancelled ())
                return;

            // Уступаем управление главному циклу на 50мс
            Timeout.add (50, perform_full_disk_search_async.callback);
            yield;
        }

        // Если поиск был отменен, пока мы ждали — выходим
        if (current_run_cancellable.is_cancelled ())
            return;

        var search_cache_tmp = new Gee.ArrayList<SearchResult> ();
        foreach (var task in tasks) {
            search_cache_tmp.add_all (task.results);
        }

        // 2. Отбираем для текущего отображения (>50)
        var all_task_results = new Gee.ArrayList<SearchResult> ();
        foreach (var res in search_cache_tmp) {
            if (res.score > 50)all_task_results.add (res);
        }

        LoggerService.get_instance ().debug ("SEARCH TEXT", "results count=" + all_task_results.size.to_string ());
        if (all_task_results.size > 4000) {
            var top_results = new Gee.TreeSet<SearchResult> ((a, b) => {
                // Сортируем по score (убывание). Если score равны, сравниваем пути для уникальности
                int res = b.score - a.score;
                if (res == 0) {
                    int path_res = a.file_path.ascii_casecmp (b.file_path);
                    if (path_res == 0) {
                        return a.line_number - b.line_number;
                    }
                }
                return res;
            });

            foreach (var task in tasks) {
                if (current_run_cancellable.is_cancelled ())return;

                foreach (var match in task.results) {
                    top_results.add (match);

                    // Если перешагнули лимит — удаляем самый «слабый» (последний) элемент
                    if (top_results.size > MAX_RESULTS) {
                        top_results.remove (top_results.last ());
                    }
                }
            }

            // Теперь all_results просто копирует готовый топ-200
            all_results = new Gee.ArrayList<SearchResult> ();
            all_results.add_all (top_results);
        } else {
            all_task_results.sort ((a, b) => b.score - a.score);

            all_results = new Gee.ArrayList<SearchResult> ();
            for (int i = 0; i < all_task_results.size && i < MAX_RESULTS; i++) {
                all_results.add (all_task_results[i]);
            }
        }

        // 1. Наполняем кэш всеми результатами (>20)
        search_cache = search_cache_tmp;
        cache_query = current_query;

        update_results ();
    }

    private void search_files_in_task (SearchTask task) {
        // Лимит на количество находок в одном конкретном файле

        foreach (var file_entry in task.files) {
            if (task.cancellable.is_cancelled ())
                return;

            try {
                var file = GLib.File.new_for_path (file_entry.path);
                var dis = new DataInputStream (file.read ());
                string line;
                int line_num = 0;
                int matches_in_this_file = 0;

                while ((line = dis.read_line ()) != null) {
                    if (task.cancellable.is_cancelled ())
                        return;

                    var matches = new Gee.ArrayList<MatchRange> ();
                    int score = fuzzy_match_with_positions (line, task.query, matches);

                    if (score > 20) {
                        // Если уже нашли достаточно в этом файле — переходим к следующему
                        if (matches_in_this_file >= 50) {
                            break;
                        }
                        matches_in_this_file++;

                        task.results.add (new SearchResult (
                                                            file_entry.path,
                                                            file_entry.relative_path,
                                                            line_num,
                                                            line,
                                                            matches,
                                                            null,
                                                            score
                        ));
                    }
                    line_num++;
                }
                dis.close ();
            } catch (Error e) {
            }
        }
    }

    private void update_results () {
        results_view.update_results (all_results);

        // ВЫКЛЮЧАЕМ ИНДИКАТОР ЗАГРУЗКИ
        spinner.stop ();
        status_stack.visible_child_name = "ready";
    }

    private void open_selected (bool close_search = true) {
        if (results_view.open_selected () && close_search) {
            close_requested ();
        }
    }

    public void start_search (string query) {
        search_entry.set_text (query);
    }

    public void handle_activated () {
        spinner.stop ();
        status_stack.visible_child_name = "ready";
        search_entry.grab_focus ();
    }
}