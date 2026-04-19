using Gee;
using Adw;

public class Iide.DiagnosticsRow : Adw.ActionRow {
    private IdeLspDiagnostic diagnostic;
    private string uri;

    public DiagnosticsRow (string uri, IdeLspDiagnostic diagnostic) {
        Object (
                title: diagnostic.message,
                subtitle: @"Line $(diagnostic.start_line + 1)",
                activatable: true
        );
        this.diagnostic = diagnostic;
        this.uri = uri;

        var icon = new Gtk.Image.from_icon_name (
                                                 (diagnostic.severity == 1)
                                                 ? "dialog-error-symbolic"
                                                 : "dialog-warning-symbolic"
        );
        icon.add_css_class ((diagnostic.severity == 1) ? "error" : "warning");
        add_prefix (icon);
    }
}

public class Iide.FileRow : Adw.ExpanderRow {
    // МЕНЯЕМ Box на ListBox
    private Gtk.ListBox content_list;
    private string uri;

    public FileRow (string uri) {
        Object (title: Path.get_basename (uri.replace ("file://", "")));
        this.uri = uri;

        // Используем ListBox для поддержки сигналов activated
        content_list = new Gtk.ListBox ();
        // content_list.add_css_class ("boxed-list"); // Придает стиль связанных строк
        content_list.set_selection_mode (Gtk.SelectionMode.NONE);

        // Добавляем ListBox в экспандер
        add_row (content_list);
    }

    public void update_rows (Gee.List<IdeLspDiagnostic>? diags) {
        // Очистка ListBox
        Gtk.Widget? child;
        while ((child = content_list.get_first_child ()) != null) {
            content_list.remove (child);
        }

        subtitle = @"$(diags.size) issues";
        if (diags != null) {
            foreach (var diag in diags) {
                var row = new DiagnosticsRow (uri, diag);

                // ОБЯЗАТЕЛЬНО: пробрасываем сигнал клика
                row.activated.connect (() => {
                    // Теперь сюда ДОЛЖНО заходить
                    var file = GLib.File.new_for_uri (uri);
                    DocumentManager.get_instance ().open_document_with_selection (file, diag.start_line, 0, 0, null);
                });

                content_list.append (row);
            }
        }
    }
}

public class Iide.DiagnosticsPanel : Panel.Widget {
    private Gtk.ScrolledWindow scrolled;
    private Gtk.ListBox main_list;
    private Adw.StatusPage empty_page;

    // Кэш для быстрого доступа к строкам файлов: [URI] -> ExpanderRow
    private HashMap<string, FileRow> file_rows = new HashMap<string, FileRow> ();
    // Кэш для заголовков серверов: [ClientID] -> Label
    private HashMap<int, Gtk.Widget> server_headers = new HashMap<int, Gtk.Widget> ();

    public DiagnosticsPanel () {
        Object (title : "Diagnostics", icon_name: "dialog-error-symbolic");

        main_list = new Gtk.ListBox ();
        main_list.set_selection_mode (Gtk.SelectionMode.NONE);

        scrolled = new Gtk.ScrolledWindow () {
            vexpand = true,
            child = main_list
        };

        empty_page = new Adw.StatusPage () {
            title = "No issues found",
            icon_name = "emblem-ok-symbolic",
            vexpand = true
        };

        this.set_child (empty_page);

        var service = DiagnosticsService.get_instance ();
        // Подключаемся к точечному обновлению вместо глобального
        service.diagnostics_updated.connect (on_file_diagnostics_updated);
        service.total_count_changed.connect (on_total_changed);
    }

    private void on_total_changed (int e, int w) {
        // Переключаем "пустое состояние" только если нужно
        if (e == 0 && w == 0) {
            if (this.get_child () != empty_page)this.set_child (empty_page);
        } else {
            if (this.get_child () != scrolled)this.set_child (scrolled);
        }
    }

    // Тот самый метод дифференциального обновления
    private void on_file_diagnostics_updated (int client_id, string uri) {
        var service = DiagnosticsService.get_instance ();
        var diags = service.get_diagnostics_for_file (client_id, uri);

        // 1. Если ошибок для файла больше нет — удаляем его строку
        if (diags == null || diags.size == 0) {
            if (file_rows.has_key (uri)) {
                var row = file_rows.get (uri);
                main_list.remove (row);
                file_rows.unset (uri);
            }
            return;
        }

        // 2. Убеждаемся, что заголовок сервера существует
        ensure_server_header (client_id);

        // 3. Обновляем или создаем строку файла
        FileRow file_row;
        if (file_rows.has_key (uri)) {
            file_row = file_rows.get (uri);
        } else {
            file_row = new FileRow (uri);
            main_list.append (file_row);
            file_rows.set (uri, file_row);
        }

        file_row.update_rows (diags);
    }

    private void ensure_server_header (int client_id) {
        if (!server_headers.has_key (client_id)) {
            var service = DiagnosticsService.get_instance ();
            var header = new Gtk.Label (service.get_server_name (client_id)) {
                xalign = 0, margin_start = 12, margin_top = 12, margin_bottom = 6
            };
            header.add_css_class ("heading");
            main_list.append (header);
            server_headers.set (client_id, header);
        }
    }
}
