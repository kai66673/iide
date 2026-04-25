public class Iide.FzfSearchEngine : SearchEngine, Object {

    private Iide.ProjectManager project_manager;

    private const int MAX_RESULTS = 100;

    public FzfSearchEngine () {
        Object ();
        project_manager = ProjectManager.get_instance ();
    }

    public string search_entry_placeholder () {
        return _("Enter file name (min 3 chars)...");
    }

    public string search_progress_message () {
        return _("Searching files...");
    }

    public string search_kind () {
        return "files";
    }

    public string search_title () {
        return _("Files");
    }

    public string search_icon_name () {
        return "document-open-symbolic";
    }

    public async Gee.List<SearchResult> perform_search (string query, GLib.Cancellable cancellable) throws Error {
        var cache = yield ensure_file_cache ();

        return perform_search_sync (query, cache);
    }

    public async Gee.List<Iide.FileEntry> ensure_file_cache () {
        if (project_manager.cache_valid) {
            return project_manager.get_file_cache ();
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

        return project_manager.get_file_cache ();
    }

    private Gee.List<SearchResult> perform_search_sync (string current_query, Gee.List<Iide.FileEntry>? cache) {
        var all_results = new Gee.ArrayList<SearchResult> ();
        if (cache == null) {
            return all_results;
        }

        var query = current_query.down ();

        {
            foreach (var f in cache) {
                var matches = new Gee.ArrayList<MatchRange> ();
                int score = fuzzy_match_with_positions (f.name.down (), query, matches);

                if (score > 20) {
                    all_results.add (new SearchResult (f.path,
                                                       f.relative_path,
                                                       -1,
                                                       f.name,
                                                       matches,
                                                       null,
                                                       score));
                    if (all_results.size >= MAX_RESULTS)break;
                }
            }
        }

        return all_results;
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
}