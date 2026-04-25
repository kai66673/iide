public class Iide.TextSearchEngine : SearchEngine, Object {

    private Iide.ProjectManager project_manager;

    private Gee.List<SearchResult> search_cache = new Gee.ArrayList<SearchResult> ();
    private string cache_query = "";
    private ThreadPool<SearchTask> thread_pool;

    private const int MAX_RESULTS = 100;

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

    public TextSearchEngine () {
        Object ();
        project_manager = ProjectManager.get_instance ();

        // 1. Инициализируем пул ОДИН РАЗ в конструкторе
        try {
            thread_pool = new ThreadPool<SearchTask>.with_owned_data ((task) => { this.search_files_in_task (task); },
                (int) GLib.get_num_processors (),
                false);
        } catch (ThreadError e) {
            critical ("Ошибка пула потоков: %s", e.message);
        }
    }

    public string search_entry_placeholder () {
        return _("Enter text (min 3 chars)...");
    }

    public string search_progress_message () {
        return _("Searching text in files...");
    }

    public string search_kind () {
        return "text";
    }

    public string search_title () {
        return _("Text");
    }

    public string search_icon_name () {
        return "edit-find-symbolic";
    }

    public async Gee.List<SearchResult> perform_search (string query, GLib.Cancellable cancellable) throws Error {
        var cache = yield ensure_file_cache ();

        return yield inner_perform_search (query, cache, cancellable);
    }

    public async Gee.List<Iide.FileEntry> ensure_file_cache () {
        if (project_manager.cache_valid) {
            return project_manager.get_text_file_cache ();
        }

        // 1. Создаем переменную для ID обработчика
        ulong handler_id = 0;

        // 2. Используем замыкание, которое вызывает callback асинхронного метода
        handler_id = project_manager.file_cache_updated.connect (() => {
            // Отключаем сигнал сразу после срабатывания (чтобы не сработал дважды)
            SignalHandler.disconnect (project_manager, handler_id);

            // Возобновляем выполнение async метода
            ensure_file_cache.callback ();
        });

        // 3. Приостанавливаем метод
        yield;

        return project_manager.get_text_file_cache ();
    }

    private async Gee.List<SearchResult> inner_perform_search (string current_query,
                                                               Gee.List<Iide.FileEntry>? cache,
                                                               GLib.Cancellable search_cancellable) {
        var all_results = new Gee.ArrayList<SearchResult> ();
        if (cache == null) {
            return all_results;
        }

        string new_query = current_query.strip ();

        // Проверка: можем ли использовать кэш?
        // Условие: кэш не пуст И новый запрос является продолжением того, что в кэше
        bool can_use_cache = search_cache.size > 0 &&
            cache_query.length > 0 &&
            new_query.has_prefix (cache_query);

        if (can_use_cache) {
            // УТОЧНЯЮЩИЙ ПОИСК (Мгновенно)
            return filter_cache_to_ui (new_query);
        } else {
            // ПОЛНЫЙ ПОИСК (Диск + Потоки)

            // Очищаем кэш
            cache_query = "";
            search_cache = new Gee.ArrayList<SearchResult> ();

            // Выполняем тяжелую работу
            return yield perform_full_disk_search_async (new_query, search_cancellable);
        }
    }

    private Gee.List<SearchResult> filter_cache_to_ui (string query) {
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
        return filtered_results;
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

    private async Gee.List<SearchResult> perform_full_disk_search_async (string current_query, Cancellable current_run_cancellable) {
        var text_files = project_manager.get_text_file_cache ();
        if (text_files == null || text_files.size == 0) {
            return new Gee.ArrayList<SearchResult> ();
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
            } catch (ThreadError e) { /* handle error */
            }
        }

        // 2. Вместо thread.join() — асинхронное ожидание
        // Мы будем проверять пул в цикле, не блокируя UI
        while (thread_pool.get_num_threads () > 0 || thread_pool.unprocessed () > 0) {
            if (current_run_cancellable.is_cancelled ())
                return new Gee.ArrayList<SearchResult> ();

            // Уступаем управление главному циклу на 50мс
            Timeout.add (50, perform_full_disk_search_async.callback);
            yield;
        }

        // Если поиск был отменен, пока мы ждали — выходим
        if (current_run_cancellable.is_cancelled ())
            return new Gee.ArrayList<SearchResult> ();

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
        var all_results = new Gee.ArrayList<SearchResult> ();
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
                if (current_run_cancellable.is_cancelled ())
                    return new Gee.ArrayList<SearchResult> ();

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

        return all_results;
    }
}