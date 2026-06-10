/*
*/
public class Iide.BookmarkRow : Adw.ActionRow {
    private string uri;
    int line_number;
    string line_text;

    public BookmarkRow(string uri, int line_number, string line_text) {
        Object (
            title: line_text,
            subtitle: @"Line $(line_number + 1)",
            activatable: true
        );

        this.uri = uri;
        this.line_number = line_number;
        this.line_text = line_text;
    }
}

public class Iide.DocumentBookmarksRow : Adw.ExpanderRow {
    private Gtk.ListBox content_list;
    private string uri;
    private BookmarkRow? active_row = null;

    public signal void child_activated (DocumentBookmarksRow self);

    public DocumentBookmarksRow(string uri) {
        Object (title: Path.get_basename (uri.replace ("file://", "")));
        this.uri = uri;

        // Добавляем ListBox в экспандер
        content_list = new Gtk.ListBox ();
        content_list.set_selection_mode (Gtk.SelectionMode.NONE);
        add_row (content_list);
    }

    private BookmarkRow create_child_row(string uri, int line_number, string line_text) {
        var row = new BookmarkRow (uri, line_number, line_text);
        row.activated.connect (() => {
            var file = GLib.File.new_for_uri (uri);
            DocumentManager.get_instance ().open_document_with_selection (file, line_number, 0, 0, null);
            this.active_row = row;
            this.child_activated (this);
        });
        return row;
    }

    public void activate_first_child () {
        this.content_list.get_row_at_index(0).activate ();
        this.expanded = true;
    }

    public void activate_last_child () {
        uint row_count = this.content_list.observe_children().get_n_items();
        this.content_list.get_row_at_index((int) row_count - 1).activate ();
        this.expanded = true;
    }

    public bool activate_next_child () {
        if (this.active_row == null) {
            this.activate_first_child ();
            this.expanded = true;
            return true;
        }

        int curr_idx = this.active_row.get_index ();
        int row_count = (int) this.content_list.observe_children().get_n_items();
        if (curr_idx == row_count - 1)
            return false;

        curr_idx++;
        this.content_list.get_row_at_index (curr_idx).activate ();
        this.expanded = true;
        return true;
    }

    public bool activate_prev_child() {
        if (this.active_row == null) {
            this.activate_last_child ();
            this.expanded = true;
            return true;
        }

        int curr_idx = this.active_row.get_index ();
        if (curr_idx == 0)
            return false;

        curr_idx--;
        this.content_list.get_row_at_index (curr_idx).activate ();
        this.expanded = true;
        return true;
    }
    
    public void update_rows (string uri, Gee.HashMap<int, string> file_lines) {
        // Очистка ListBox
        Gtk.Widget? child;
        while ((child = content_list.get_first_child ()) != null) {
            content_list.remove (child);
        }
        this.active_row = null;

        foreach (var file_line in file_lines.entries) {
            content_list.append (this.create_child_row(uri, file_line.key, file_line.value));
        }
    }
}

public class Iide.BookmarksView : Gtk.Box {
    private Gtk.ScrolledWindow scrolled;
    private Gtk.ListBox main_list;
    private DocumentBookmarksRow? active_file_row = null;

    // Кэш для быстрого доступа к строкам файлов: [URI] -> ExpanderRow
    private Gee.HashMap<string, DocumentBookmarksRow> file_rows = new Gee.HashMap<string, DocumentBookmarksRow> ();

    public BookmarksView () {
        main_list = new Gtk.ListBox ();
        main_list.set_selection_mode (Gtk.SelectionMode.NONE);

        scrolled = new Gtk.ScrolledWindow () {
            vexpand = true,
            hexpand = true,
            child = main_list
        };

        this.append (scrolled);

        var bookmarks_navigator = BookmarksNavigator.get_instance ();
        bookmarks_navigator.document_bookmarks_changed.connect(
            this.update_buffer_bookmarks
        );
        bookmarks_navigator.project_bookmarks_loaded.connect(
            this.update_project_bookmarks
        );
        bookmarks_navigator.goto_next_bookmark.connect(
            this.activate_next_bookmark
        );
        bookmarks_navigator.goto_prev_bookmark.connect(
            this.activate_prev_bookmark
        );
    }

    private void activate_next_bookmark() {
        if (this.file_rows.size == 0)
            return;

        if (this.active_file_row == null) {
            var first_file_row = main_list.get_row_at_index(0) as DocumentBookmarksRow;
            first_file_row? . activate_first_child ();
            return;
        }

        if (this.active_file_row.activate_next_child ())
            return;

        int curr_idx = this.active_file_row.get_index ();
        int row_count = (int) this.main_list.observe_children().get_n_items();
        if (curr_idx == row_count - 1) {
            var first_file_row = this.main_list.get_row_at_index (0) as DocumentBookmarksRow;
            first_file_row? . activate_first_child ();
        } else {
            curr_idx++;
            var next_file_row = this.main_list.get_row_at_index (curr_idx) as DocumentBookmarksRow;
            next_file_row? . activate_first_child ();
        }
    }

    private void activate_prev_bookmark() {
        if (this.file_rows.size == 0)
            return;

        if (this.active_file_row == null) {
            int row_count = (int) this.main_list.observe_children().get_n_items();
            var last_file_row = main_list.get_row_at_index(row_count - 1) as DocumentBookmarksRow;
            last_file_row? . activate_last_child ();
            return;
        }

        if (this.active_file_row.activate_prev_child ())
            return;

        int curr_idx = this.active_file_row.get_index ();
        if (curr_idx == 0) {
            int row_count = (int) this.main_list.observe_children().get_n_items();
            var last_file_row = main_list.get_row_at_index(row_count - 1) as DocumentBookmarksRow;
            last_file_row? . activate_last_child ();
        } else {
            curr_idx--;
            var prev_file_row = this.main_list.get_row_at_index (curr_idx) as DocumentBookmarksRow;
            prev_file_row? . activate_last_child ();
        }
    }

    private void update_project_bookmarks(Gee.HashMap<string, Gee.ArrayList<int>> bookmarks) {
        // Очистка ListBox
        Gtk.Widget? child;
        while ((child = main_list.get_first_child ()) != null) {
            main_list.remove (child);
        }
        file_rows.clear ();
        this.active_file_row = null;

        foreach (var file_bookmarks in bookmarks.entries) {
            var file_uri = file_bookmarks.key;
            var line_numbers = file_bookmarks.value;
            Gee.HashMap<int, string> file_lines = new Gee.HashMap<int, string> ();
            foreach (var line_number in line_numbers) {
                file_lines.set (line_number, "...");  // TODO: ?
            }
            var file_row = new DocumentBookmarksRow (file_uri);
            main_list.append (file_row);
            file_rows.set (file_uri, file_row);
            file_row.update_rows (file_uri, file_lines);
            file_row.child_activated.connect ((row) => {
                this.active_file_row = row;
            });
        }
    }


    private string iter_line_text(Gtk.TextIter iter) {
        Gtk.TextIter start_iter = iter;
        Gtk.TextIter end_iter = iter;

        start_iter.set_line_offset(0);
        end_iter.forward_to_line_end();

        return iter.get_buffer ().get_text(start_iter, end_iter, true);
    }

    private void update_buffer_bookmarks (string file_uri, Gtk.TextBuffer buffer) {
        var source_buffer = buffer as GtkSource.Buffer;
        if (source_buffer == null)
            return;
        
        Gtk.TextIter iter;
        source_buffer.get_start_iter (out iter);

        var current_file_lines = new Gee.HashMap<int, string> ();

        // Идем по буферу вперед, прыгая строго от маркера к маркеру категории "bookmark" [INDEX]
        while (!iter.is_end ()) {
            // Проверяем, есть ли на текущей позиции маркера закладка [INDEX]
            var marks_at_pos = source_buffer.get_source_marks_at_line (iter.get_line (), "bookmark");
            if (marks_at_pos != null && marks_at_pos.length () > 0) {
                int line_num = iter.get_line ();
                // Чтобы избежать дублирования на одной строке, проверяем наличие
                if (!current_file_lines.has_key (line_num)) {
                    current_file_lines.set (line_num, iter_line_text (iter));
                }
            }

            // Перемещаем итератор к СЛЕДУЮЩЕМУ маркеру категории "bookmark".
            // Это работает в разы быстрее, чем посимвольный перебор всего файла! [INDEX]
            if (!source_buffer.forward_iter_to_source_mark (ref iter, "bookmark")) {
                break; // Если маркеров впереди больше нет — завершаем цикл [INDEX]
            }
        }

        // Записываем собранные строки в кэш
        if (current_file_lines.size > 0) {
            DocumentBookmarksRow file_row;
            if (file_rows.has_key (file_uri)) {
                file_row = file_rows.get (file_uri);
            } else {
                file_row = new DocumentBookmarksRow (file_uri);
                main_list.append (file_row);
                file_rows.set (file_uri, file_row);
                file_row.child_activated.connect ((row) => {
                    this.active_file_row = row;
                });
            }
            file_row.update_rows (file_uri, current_file_lines);     
        } else {
            // Если пользователь снял все закладки — очищаем записи
            if (file_rows.has_key (file_uri)) {
                var row = file_rows.get (file_uri);
                main_list.remove (row);
                if (this.active_file_row == row) {
                    this.active_file_row = null;
                }
                file_rows.unset (file_uri);
            }
        }
    }
}