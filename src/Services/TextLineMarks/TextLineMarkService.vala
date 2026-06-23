/*
*/

public class Iide.TextLineMarkService : GLib.Object {
    private static TextLineMarkService? _instance = null;
    private string? current_project_root = null;
    private LoggerService logger;

    public string category { get; construct; }

    // Кэш закладок в памяти для файлов, пока они не открыты в UI
    // [file_uri] -> [Список номеров строк (0-indexed)]
    private Gee.HashMap<string, Gee.ArrayList<TextLineMark?>> loaded_json_cache;

    public static TextLineMarkService get_instance () {
        return _instance;
    }

    public TextLineMarkService (string category) {
        Object(category: category);
        TextLineMarkService._instance = this;
        this.logger = LoggerService.get_instance ();
        this.loaded_json_cache = new Gee.HashMap<string, Gee.ArrayList<TextLineMark?>> ();
    }

    /**
     * Инициализация проекта. Вызывается при открытии рабочей папки IDE.
     */
    public void init_project (string project_root_path) {
        this.current_project_root = project_root_path;
        this.loaded_json_cache.clear ();
        this.load_marks_from_json ();
        BookmarksNavigator.get_instance ().project_bookmarks_loaded (this.loaded_json_cache);
    }

    /**
     * ФАЗА 1: ЗАГРУЗКА ЗАКЛАДОК В ТЕКСТОВЫЙ РЕДАКТОР.
     * Вызывается, когда файл только что загрузился с диска в SourceView.
     */
    public void refresh_all_documents_marks() {
        foreach (var doc in DocumentManager.get_instance ().documents.values) {
            this.apply_marks_to_buffer (doc.uri, doc.source_view.buffer);
        }
    }

    public void apply_marks_to_buffer (string file_uri, Gtk.TextBuffer buffer) {
        var source_buffer = buffer as GtkSource.Buffer;
        if (source_buffer == null)
            return;

        // Очищаем все закладки
        Gtk.TextIter start, end;
        source_buffer.get_start_iter(out start);
        source_buffer.get_end_iter(out end);
        source_buffer.remove_source_marks (start, end, this.category);

        // Если для этого файла нет сохраненных закладок — выходим
        if (!this.loaded_json_cache.has_key (file_uri))
            return;
        
        var marks_info = this.loaded_json_cache.get (file_uri);

        foreach (var mark_info in marks_info) {
            // Страхуемся от выхода за границы, если файл успели обрезать извне
            if (mark_info.line_number >= source_buffer.get_line_count ()) continue;

            Gtk.TextIter line_iter;
            source_buffer.get_iter_at_line (out line_iter, mark_info.line_number);

            source_buffer.create_source_mark (null, this.category, line_iter);
        }

        this.logger.info ("MRK", "Successfully spawned %d '%s' marks for: %s".printf (
            marks_info.size, this.category, file_uri));
    }

    private string iter_line_text(Gtk.TextIter iter) {
        Gtk.TextIter start_iter = iter;
        Gtk.TextIter end_iter = iter;

        start_iter.set_line_offset(0);
        end_iter.forward_to_line_end();

        return iter.get_buffer ().get_text(start_iter, end_iter, true);
    }

    public void update_buffer_marks (string file_uri, Gtk.TextBuffer buffer) {
        var source_buffer = buffer as GtkSource.Buffer;
        if (source_buffer == null)
            return;
        
        Gtk.TextIter iter;
        source_buffer.get_start_iter (out iter);

        var current_file_marks = new Gee.HashMap<int, TextLineMark?> ();

        // Идем по буферу вперед, прыгая строго от маркера к маркеру категории
        while (!iter.is_end ()) {
            // Проверяем, есть ли на текущей позиции маркера закладка
            var marks_at_pos = source_buffer.get_source_marks_at_line (iter.get_line (), this.category);
            if (marks_at_pos != null && marks_at_pos.length () > 0) {
                int line_num = iter.get_line ();
                // Чтобы избежать дублирования на одной строке, проверяем наличие
                if (!current_file_marks.has_key (line_num)) {
                    TextLineMark mark = TextLineMark () {
                        line_number = line_num,
                        line_text = iter_line_text(iter)
                    };
                    current_file_marks.set (line_num, mark);
                }
            }

            // Перемещаем итератор к СЛЕДУЮЩЕМУ маркеру категории.
            if (!source_buffer.forward_iter_to_source_mark (ref iter, this.category)) {
                break; // Если маркеров впереди больше нет — завершаем цикл [INDEX]
            }
        }

        // Записываем собранные строки в кэш
        if (current_file_marks.size > 0) {
            Gee.ArrayList<TextLineMark?> file_marks = new Gee.ArrayList<TextLineMark?> ();
            foreach (var mark in current_file_marks.values) {
                file_marks.add (mark);
            }
            this.loaded_json_cache.set (file_uri, file_marks);
        } else {
            // Если пользователь снял все закладки — очищаем запись файла из кэша
            this.loaded_json_cache.unset (file_uri);
        }
    }

    /**
     * ФАЗА 2: СБОР ЗАКЛАДОК ИЗ РЕДАКТОРА И ЗАПИСЬ НА ДИСК.
     * Вызывается при сохранении документов или закрытии воркспейса.
     */
    public void save_marks_from_active_buffers (Gee.Collection<SourceView> active_views) {
        if (this.current_project_root == null) return;

        // Обновляем кэш в памяти данными из открытых вкладок редактора
        foreach (var view in active_views) {
            this.update_buffer_marks (view.uri, view.buffer);
        }

        // Физически сохраняем обновленный кэш в .iide/`category`.json
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
                foreach (var mark in entry.value) {
                    var mark_obj = new Json.Object ();
                    mark_obj.set_int_member ("line_number", mark.line_number);
                    mark_obj.set_string_member ("line_text", mark.line_text);
                    lines_array.add_object_element (mark_obj);
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
            this.logger.error ("MRK", "Failed to write bookmarks.json: %s".printf (e.message));
        }
    }

    // Внутренний метод чтения JSON при старте проекта
    private void load_marks_from_json () {
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
                var marks = new Gee.ArrayList<TextLineMark?> ();

                foreach (var element in lines_array.get_elements ()) {
                    var mark_obj = element.get_object ();
                    marks.add (
                        TextLineMark() {
                            line_number = (int) mark_obj.get_int_member ("line_number"),
                            line_text = mark_obj.get_string_member ("line_text")
                        }
                    );
                }

                if (marks.size > 0) {
                    this.loaded_json_cache.set (file_uri, marks);
                }
            }
            this.logger.info ("MRK", "Marks matrix `%s` loaded successfully from project storage.".printf (this.category));
        } catch (GLib.Error e) {
            this.logger.error ("MRK", "Failed to read %s.json: %s".printf (this.category, e.message));
        }
    }

    public void clear_project_marks() {
        this.loaded_json_cache.clear ();
        this.write_cache_to_json_file ();
        BookmarksNavigator.get_instance ().project_bookmarks_loaded (this.loaded_json_cache);
        this.refresh_all_documents_marks ();
    }
}

