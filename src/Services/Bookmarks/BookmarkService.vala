/*
*/

public class Iide.BookmarkService : GLib.Object {
    private static BookmarkService? instance = null;
    private string? current_project_root = null;

    // Кэш закладок в памяти для файлов, пока они не открыты в UI
    // [file_uri] -> [Список номеров строк (0-indexed)]
    private Gee.HashMap<string, Gee.ArrayList<BookMarkInfo?>> loaded_json_cache;

    public static BookmarkService get_instance () {
        if (instance == null) {
            instance = new BookmarkService ();
        }
        return instance;
    }

    private BookmarkService () {
        Object ();
        this.loaded_json_cache = new Gee.HashMap<string, Gee.ArrayList<BookMarkInfo?>> ();
    }

    /**
     * Инициализация проекта. Вызывается при открытии рабочей папки IDE.
     */
    public void init_project (string project_root_path) {
        this.current_project_root = project_root_path;
        this.loaded_json_cache.clear ();
        this.load_bookmarks_from_json ();
        BookmarksNavigator.get_instance ().project_bookmarks_loaded (this.loaded_json_cache);
    }

    /**
     * ФАЗА 1: ЗАГРУЗКА ЗАКЛАДОК В ТЕКСТОВЫЙ РЕДАКТОР.
     * Вызывается, когда файл только что загрузился с диска в SourceView.
     */
    public void refresh_all_documents_bookmarks() {
        foreach (var doc in DocumentManager.get_instance ().documents.values) {
            this.apply_bookmarks_to_buffer (doc.uri, doc.source_view.buffer);
        }
    }

    public void apply_bookmarks_to_buffer (string file_uri, Gtk.TextBuffer buffer) {
        var source_buffer = buffer as GtkSource.Buffer;
        if (source_buffer == null)
            return;

        // Очищаем все закладки
        Gtk.TextIter start, end;
        source_buffer.get_start_iter(out start);
        source_buffer.get_end_iter(out end);
        source_buffer.remove_source_marks (start, end, "bookmark");

        // Если для этого файла нет сохраненных закладок — выходим
        if (!this.loaded_json_cache.has_key (file_uri))
            return;
        
        var bookmarks_info = this.loaded_json_cache.get (file_uri);

        foreach (var bookmark_info in bookmarks_info) {
            // Страхуемся от выхода за границы, если файл успели обрезать извне
            if (bookmark_info.line_number >= source_buffer.get_line_count ()) continue;

            Gtk.TextIter line_iter;
            source_buffer.get_iter_at_line (out line_iter, bookmark_info.line_number);

            // Создаем нативный GtkSource.Mark категории "bookmark" [INDEX]
            source_buffer.create_source_mark (null, "bookmark", line_iter);
        }

        LoggerService.get_instance ().info ("Bookmarks", "Successfully spawned %d 'bookmark' marks for: %s".printf (bookmarks_info.size, file_uri));
    }

    private string iter_line_text(Gtk.TextIter iter) {
        Gtk.TextIter start_iter = iter;
        Gtk.TextIter end_iter = iter;

        start_iter.set_line_offset(0);
        end_iter.forward_to_line_end();

        return iter.get_buffer ().get_text(start_iter, end_iter, true);
    }

    public void update_buffer_bookmarks (string file_uri, Gtk.TextBuffer buffer) {
        var source_buffer = buffer as GtkSource.Buffer;
        if (source_buffer == null)
            return;
        
        Gtk.TextIter iter;
        source_buffer.get_start_iter (out iter);

        var current_file_bookmarks = new Gee.HashMap<int, BookMarkInfo?> ();

        // Идем по буферу вперед, прыгая строго от маркера к маркеру категории "bookmark" [INDEX]
        while (!iter.is_end ()) {
            // Проверяем, есть ли на текущей позиции маркера закладка [INDEX]
            var marks_at_pos = source_buffer.get_source_marks_at_line (iter.get_line (), "bookmark");
            if (marks_at_pos != null && marks_at_pos.length () > 0) {
                int line_num = iter.get_line ();
                // Чтобы избежать дублирования на одной строке, проверяем наличие
                if (!current_file_bookmarks.has_key (line_num)) {
                    BookMarkInfo bookmark = BookMarkInfo () {
                        line_number = line_num,
                        line_text = iter_line_text(iter)
                    };
                    current_file_bookmarks.set (line_num, bookmark);
                }
            }

            // Перемещаем итератор к СЛЕДУЮЩЕМУ маркеру категории "bookmark".
            // Это работает в разы быстрее, чем посимвольный перебор всего файла! [INDEX]
            if (!source_buffer.forward_iter_to_source_mark (ref iter, "bookmark")) {
                break; // Если маркеров впереди больше нет — завершаем цикл [INDEX]
            }
        }

        // Записываем собранные строки в кэш
        if (current_file_bookmarks.size > 0) {
            Gee.ArrayList<BookMarkInfo?> file_bookmarks = new Gee.ArrayList<BookMarkInfo?> ();
            foreach (var bookmark in current_file_bookmarks.values) {
                file_bookmarks.add (bookmark);
            }
            this.loaded_json_cache.set (file_uri, file_bookmarks);
        } else {
            // Если пользователь снял все закладки — очищаем запись файла из кэша
            this.loaded_json_cache.unset (file_uri);
        }
    }

    /**
     * ФАЗА 2: СБОР ЗАКЛАДОК ИЗ РЕДАКТОРА И ЗАПИСЬ НА ДИСК.
     * Вызывается при сохранении документов или закрытии воркспейса.
     */
    public void save_bookmarks_from_active_buffers (Gee.Collection<SourceView> active_views) {
        if (this.current_project_root == null) return;

        // Обновляем кэш в памяти данными из открытых вкладок редактора
        foreach (var view in active_views) {
            this.update_buffer_bookmarks (view.uri, view.buffer);
        }

        // Физически сохраняем обновленный кэш в .iide/bookmarks.json
        this.write_cache_to_json_file ();
    }

    // Внутренний метод записи в JSON
    public void write_cache_to_json_file () {
        string config_dir = Path.build_filename (this.current_project_root, ".iide");
        string config_path = Path.build_filename (config_dir, "bookmarks.json");

        try {
            if (!FileUtils.test (config_dir, FileTest.EXISTS)) {
                DirUtils.create_with_parents (config_dir, 0755);
            }

            var root_obj = new Json.Object ();
            var files_obj = new Json.Object ();

            foreach (var entry in this.loaded_json_cache.entries) {
                var lines_array = new Json.Array ();
                foreach (var bookmark in entry.value) {
                    var bookmark_obj = new Json.Object ();
                    bookmark_obj.set_int_member ("line_number", bookmark.line_number);
                    bookmark_obj.set_string_member ("line_text", bookmark.line_text);
                    lines_array.add_object_element (bookmark_obj);
                }
                files_obj.set_array_member (entry.key, lines_array);
            }

            root_obj.set_object_member ("bookmarks", files_obj);

            var generator = new Json.Generator ();
            var root_node = new Json.Node (Json.NodeType.OBJECT);
            root_node.set_object (root_obj);
            generator.set_root (root_node);
            generator.set_pretty (true);

            generator.to_file (config_path);
        } catch (GLib.Error e) {
            LoggerService.get_instance ().error ("Bookmarks", "Failed to write bookmarks.json: %s".printf (e.message));
        }
    }

    // Внутренний метод чтения JSON при старте проекта
    private void load_bookmarks_from_json () {
        string config_path = Path.build_filename (this.current_project_root, ".iide", "bookmarks.json");
        if (!FileUtils.test (config_path, FileTest.EXISTS)) return;

        try {
            var parser = new Json.Parser ();
            parser.load_from_file (config_path);

            var root = parser.get_root ().get_object ();
            if (!root.has_member ("bookmarks")) return;

            var files_obj = root.get_object_member ("bookmarks");
            foreach (string file_uri in files_obj.get_members ()) {
                var lines_array = files_obj.get_array_member (file_uri);
                var bookmarks = new Gee.ArrayList<BookMarkInfo?> ();

                foreach (var element in lines_array.get_elements ()) {
                    var bookmark_obj = element.get_object ();
                    bookmarks.add (
                        BookMarkInfo() {
                            line_number = (int) bookmark_obj.get_int_member ("line_number"),
                            line_text = bookmark_obj.get_string_member ("line_text")
                        }
                    );
                }

                if (bookmarks.size > 0) {
                    this.loaded_json_cache.set (file_uri, bookmarks);
                }
            }
            LoggerService.get_instance ().info ("Bookmarks", "Bookmarks matrix loaded successfully from project storage.");
        } catch (GLib.Error e) {
            LoggerService.get_instance ().error ("Bookmarks", "Failed to read bookmarks.json: %s".printf (e.message));
        }
    }
}

