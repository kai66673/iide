using Gee;
using Adw;

public class Iide.DiagnosticsRow : Adw.ActionRow {
    private LspDiagnostic diagnostic;
    private string uri;

    public DiagnosticsRow (string uri, LspDiagnostic diagnostic) {
        Object (
                title: diagnostic.message,
                subtitle: @"Line $(diagnostic.start_line + 1)",
                activatable: true
        );
        this.diagnostic = diagnostic;
        this.uri = uri;

        var icon_provider = SymbIconProvider.get_instance ();
        switch (diagnostic.severity) {
            case 1:
                //  this.icon_name = icon_provider.icon_name (IconID.COD_ERROR);
                add_prefix (icon_provider.image (IconID.COD_ERROR));
                break;
            case 2: case 3: case 4:
                //  this.icon_name = icon_provider.icon_name (IconID.COD_WARNING);
                add_prefix (icon_provider.image (IconID.COD_WARNING));
                break;
        }
    }
}

public class Iide.FileRow : Adw.ExpanderRow {
    private Gtk.ListBox content_list;
    private string uri;
    
    // Храним сырой кэш данных, чтобы строить UI только при необходимости
    private Gee.List<LspDiagnostic>? cached_diags = null;

    public FileRow (string uri) {
        Object (title: Path.get_basename (uri.replace ("file://", "")));
        this.uri = uri;

        content_list = new Gtk.ListBox ();
        content_list.set_selection_mode (Gtk.SelectionMode.NONE);
        add_row (content_list);

        // ОПТИМИЗАЦИЯ: Слушаем нативное свойство разворачивания строки в GTK4
        this.notify["expanded"].connect (() => {
            if (this.expanded) {
                this.render_cached_rows ();
            }
        });
    }

    public void update_rows (Gee.List<LspDiagnostic>? diags) {
        this.cached_diags = diags;
        
        int count = diags != null ? diags.size : 0;
        this.subtitle = @"$count issues";

        // Если строка развернута прямо сейчас — перерисовываем UI
        if (this.expanded) {
            this.render_cached_rows ();
        }
    }

    private void render_cached_rows () {
        // Очищаем внутренний ListBox
        Gtk.Widget? child;
        while ((child = content_list.get_first_child ()) != null) {
            content_list.remove (child);
        }

        if (this.cached_diags == null) return;

        // Оптимизация: Получаем синглтон иконок ОДИН раз перед циклом, а не внутри конструктора строки!
        //  var icon_provider = SymbIconProvider.get_instance ();

        foreach (var diag in this.cached_diags) {
            // Передаем провайдер иконок в конструктор, избегая лишних get_instance() на каждую ошибку
            var row = new DiagnosticsRow (uri, diag);

            row.activated.connect (() => {
                var file = GLib.File.new_for_uri (uri);
                DocumentManager.get_instance ().open_document_with_selection (file, diag.start_line, 0, 0, null);
            });

            content_list.append (row);
        }
    }
}

public class Iide.ServerDiagnosticsGroup : Adw.PreferencesGroup {
    public Gtk.ListBox file_list { get; private set; }
    public string server_name { get; private set; }

    // ИСПРАВЛЕНИЕ: Кэш строк файлов теперь инкапсулирован внутри своей группы!
    private HashMap<string, FileRow> file_rows = new HashMap<string, FileRow> ();

    public ServerDiagnosticsGroup (string server_name) {
        Object (title: server_name);
        this.server_name = server_name;

        this.file_list = new Gtk.ListBox ();
        this.file_list.set_selection_mode (Gtk.SelectionMode.NONE);
        this.file_list.add_css_class ("boxed-list");

        this.add (this.file_list);
    }

    /**
     * МЕТОД ОБНОВЛЕНИЯ ДИАГНОСТИКИ ДЛЯ КОНКРЕТНОГО ФАЙЛА ГРУППЫ
     * Возвращает true, если в группе еще остались файлы с ошибками, 
     * и false, если группа полностью опустела (нужно удалить её с экрана)
     */
    public bool update_file_diagnostics (string uri, Gee.List<LspDiagnostic>? diags) {
        // 1. Если ошибок для файла больше нет — точечно удаляем его строку из этого сервера [INDEX]
        if (diags == null || diags.size == 0) {
            if (this.file_rows.has_key (uri)) {
                var row = this.file_rows.get (uri);
                this.file_list.remove (row);
                this.file_rows.unset (uri);
            }
            // Возвращаем флаг: пуста ли группа серверов целиком [INDEX]
            return !this.file_rows.is_empty;
        }

        // 2. Ищем или лениво создаем строку файла внутри этого сервера [INDEX]
        FileRow file_row;
        if (this.file_rows.has_key (uri)) {
            file_row = this.file_rows.get (uri);
        } else {
            file_row = new FileRow (uri);
            this.file_list.append (file_row);
            this.file_rows.set (uri, file_row);
        }

        // 3. Отдаем данные на ленивый рендеринг
        file_row.update_rows (diags);
        
        return true; // В группе точно есть файлы с ошибками
    }

    /**
     * Полная очистка ресурсов при выгрузке сервера
     */
    public void clear_group () {
        this.file_rows.clear ();
        Gtk.Widget? child;
        while ((child = this.file_list.get_first_child ()) != null) {
            this.file_list.remove (child);
        }
    }
}

public class Iide.DiagnosticsPanel : BasePanel {
    private Gtk.ScrolledWindow scrolled;
    private Gtk.Box main_box; 
    private Adw.StatusPage empty_page;

    // На верхнем уровне панели остался СТРОГО ОДИН кэш — кэш групп серверов! [INDEX]
    private HashMap<string, ServerDiagnosticsGroup> server_groups = new HashMap<string, ServerDiagnosticsGroup> ();

    public DiagnosticsPanel (Window window) {
        base (window, "Diagnostics", SymbIconProvider.get_instance ().icon_name (IconID.APP_ISSUES));
        can_maximize = true;

        this.main_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 18) {
            margin_start = 12, margin_end = 12, margin_top = 12
        };

        scrolled = new Gtk.ScrolledWindow () {
            vexpand = true, child = this.main_box
        };

        empty_page = new Adw.StatusPage () {
            title = "No issues found", icon_name = "emblem-ok-symbolic", vexpand = true
        };

        this.set_child (empty_page);

        var service = DiagnosticsService.get_instance ();
        // Подключаемся к точечному обновлению вместо глобального
        service.diagnostics_updated.connect (on_file_diagnostics_updated);
        service.total_count_changed.connect (on_total_changed);
        service.lsp_stopped.connect (on_diagnostics_cleared);
        service.server_stopped.connect (on_server_stopped);
    }

    public override Panel.Position initial_pos () {
        return new Panel.Position () { area = Panel.Area.BOTTOM };
    }

    public override string panel_id () {
        return "DiagnosticsPanel";
    }

    private void on_total_changed (int e, int w) {
        // Переключаем "пустое состояние" только если нужно
        if (e == 0 && w == 0) {
            if (this.get_child () != empty_page)
                this.set_child (empty_page);
        } else {
            if (this.get_child () != scrolled)
                this.set_child (scrolled);
        }
    }

    private void on_server_stopped (string server_name) {
        if (server_groups.has_key (server_name)) {
            ServerDiagnosticsGroup group_to_remove;
            server_groups.unset (server_name, out group_to_remove);
            main_box.remove (group_to_remove);
        }
    }

    private void on_diagnostics_cleared () {
        this.set_child (empty_page);
        
        Gtk.Widget? child;
        while ((child = main_box.get_first_child ()) != null) {
            main_box.remove (child);
        }
        
        foreach (var group in server_groups.values) {
            group.clear_group ();
        }
        server_groups.clear ();
    }

    /**
     * ЧИСТЫЙ МЕТОД ДИФФЕРЕНЦИАЛЬНОГО ОБНОВЛЕНИЯ
     */
    private void on_file_diagnostics_updated (string server_name, string uri) {
        var service = DiagnosticsService.get_instance ();
        var diags = service.get_diagnostics_for_file (server_name, uri);

        // 1. Гарантируем наличие изолированной группы для этого сервера [INDEX]
        var group = this.ensure_server_group (server_name);

        // 2. Просто просим саму группу обновить состояние файла внутри себя! [INDEX]
        // Объект группы сам разберется с кэшем строк и ленивым рендерингом [INDEX].
        bool group_has_active_files = group.update_file_diagnostics (uri, diags);

        // 3. Если после обновления группа сервера полностью опустела — удаляем её с экрана
        if (!group_has_active_files) {
            this.main_box.remove (group);
            server_groups.unset (server_name);
        }
    }

    private ServerDiagnosticsGroup ensure_server_group (string server_name) {
        if (!server_groups.has_key (server_name)) {
            var group = new ServerDiagnosticsGroup (server_name);
            this.main_box.append (group);
            server_groups.set (server_name, group);
            return group;
        }
        return server_groups.get (server_name);
    }
}
