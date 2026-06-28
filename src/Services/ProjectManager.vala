using Gtk;
using GLib;
using Gee;

public class Iide.FileEntry : Object {
    public string path { get; construct; }
    public string name { get; construct; }
    public bool is_text_file { get; construct; }
    public string relative_path { get; construct; }
    public string display_name { get; construct; }

    public FileEntry (string path, string name, bool is_text_file, string relative_path) {
        Object (
                path: path,
                name: name,
                is_text_file: is_text_file,
                relative_path: relative_path,
                display_name: "%s  →  %s".printf (name, relative_path)
        );
    }
}

public class Iide.ProjectManager : Object {
    public Window window;
    private static ProjectManager? _instance = null;

    private GLib.File? current_project_root;
    private string? current_project_name;
    // Путь к скрытой папке настроек текущего проекта (/path/to/project/.iide)
    private GLib.File? iide_dir;
    private Iide.SettingsService settings;

    private Gee.List<Iide.FileEntry> file_cache;
    private Gee.List<Iide.FileEntry> text_file_cache;
    public bool cache_valid = false;
    private bool cache_loading = false;
    private FileMonitor? directory_monitor;

    private const string[] EXCLUDED_DIRS = {
        "node_modules", "target", "build", "__pycache__",
        ".git", ".svn", ".hg", "vendor", ".cargo",
        ".cache", ".local", ".config"
    };

    public signal void project_opened (GLib.File project_root);
    public signal void project_closed ();
    public signal void file_cache_updated ();
    public signal void file_cache_invalidated ();

    public static unowned ProjectManager get_instance () {
        return _instance;
    }

    public ProjectManager (Window window) {
        this.window = window;
        ProjectManager._instance = this;

        current_project_root = null;
        current_project_name = null;
        iide_dir = null;
        settings = Iide.SettingsService.get_instance ();
        file_cache = new Gee.ArrayList<Iide.FileEntry> ();
        text_file_cache = new Gee.ArrayList<Iide.FileEntry> ();
    }

    public async void open_project_folder (GLib.File project_root) {
        if (!project_root.query_exists (null)) {
            LoggerService.get_instance ().error ("PROJECT", "Project directory does not exist: %s".printf (project_root.get_path ()));
            return;
        }

        if (current_project_root != null && current_project_root.get_path () == project_root.get_path ()) {
            LoggerService.get_instance ().warning ("PROJECT", "Selected project folder already opened.");
            return;
        }

        bool save_confirmed = yield DocumentManager.get_instance ()
            .confirm_save_modified_documents_async ();

        if (!save_confirmed)
            return;

        if (current_project_root != null) {
            yield close_project ();
        }

        current_project_root = project_root;
        current_project_name = project_root.get_basename ();

        this.iide_dir = project_root.get_child (".iide");
        this.ensure_iide_directory_exists ();

        settings.current_project_path = project_root.get_path ();
        settings.add_recent_project (project_root.get_path ());
        settings.last_open_directory = project_root.get_parent ().get_path ();

        this.restore_session_and_panels ();

        foreach (var mark_service in this.window.marks_service) {
            mark_service.init_project (settings.current_project_path);
            mark_service.refresh_all_documents_marks ();
        }

        rebuild_file_cache_async.begin ();

        setup_directory_monitor (project_root);

        project_opened (project_root);
    }

    private void ensure_iide_directory_exists () {
        if (this.iide_dir != null && !this.iide_dir.query_exists (null)) {
            try {
                this.iide_dir.make_directory (null);
                LoggerService.get_instance ().info ("PROJECT", "Created internal .iide/ directory for workspace config.");
            } catch (GLib.Error e) {
                LoggerService.get_instance ().error ("PROJECT", "Failed to create .iide directory: " + e.message);
            }
        }
    }

    private void setup_directory_monitor (GLib.File dir) {
        if (directory_monitor != null) {
            directory_monitor.cancel ();
        }

        try {
            directory_monitor = dir.monitor_directory (FileMonitorFlags.NONE, null);
            directory_monitor.changed.connect ((src, dst, event) => {
                if (event == FileMonitorEvent.CHANGES_DONE_HINT) {
                    invalidate_file_cache ();
                }
            });
        } catch (Error e) {
            warning ("Failed to setup directory monitor: %s", e.message);
        }
    }

    public async void close_project () {
        if (directory_monitor != null) {
            directory_monitor.cancel ();
            directory_monitor = null;
        }

        if (current_project_root != null) {
            yield shutdown_all_running_lsp_servers_async ();
            DiagnosticsService.get_instance ().lsp_stopped ();

            current_project_root = null;
            current_project_name = null;
            cache_valid = false;
            file_cache.clear ();
            text_file_cache.clear ();
            settings.current_project_path = "";
            foreach (var mark_service in this.window.marks_service) {
                mark_service.write_cache_to_json_file ();
            }
            this.save_session_and_clear_panels ();
            project_closed ();
        }
    }

    public async void rebuild_file_cache_async () {
        if (current_project_root == null) {
            return;
        }

        if (cache_loading) {
            return;
        }

        cache_loading = true;
        file_cache.clear ();
        text_file_cache.clear ();

        try {
            yield scan_directory_async (current_project_root, current_project_root.get_path ());

            file_cache.sort ((a, b) => a.name.collate (b.name));
            text_file_cache.sort ((a, b) => a.name.collate (b.name));
            cache_valid = true;
            file_cache_updated ();
        } catch (Error e) {
            warning ("Error rebuilding file cache: %s", e.message);
        }

        cache_loading = false;
    }

    private bool is_text_file (GLib.FileInfo file_info) {
        return ContentType.is_a (file_info.get_content_type (), "text/plain");
    }

    private async void scan_directory_async (GLib.File dir, string base_path) throws Error {
        var enumerator = yield dir.enumerate_children_async ("standard::name,standard::type,standard::content-type",
            FileQueryInfoFlags.NONE,
            Priority.DEFAULT,
            null);

        while (true) {
            var files = yield enumerator.next_files_async (100, Priority.DEFAULT, null);

            if (files == null || files.length () == 0) {
                break;
            }

            foreach (var info in files) {
                var name = info.get_name ();
                if (name.has_prefix (".")) {
                    continue;
                }

                var file_type = info.get_file_type ();
                if (file_type == FileType.DIRECTORY) {
                    bool excluded = false;
                    foreach (var excluded_name in EXCLUDED_DIRS) {
                        if (name == excluded_name) {
                            excluded = true;
                            break;
                        }
                    }
                    if (!excluded) {
                        var child = dir.get_child (name);
                        yield scan_directory_async (child, base_path);
                    }
                } else if (file_type == FileType.REGULAR) {
                    var path = dir.get_child (name).get_path ();
                    if (path != null) {
                        var relative = path.substring (base_path.length + 1);
                        bool is_text = is_text_file (info);
                        file_cache.add (new Iide.FileEntry (
                                                            path,
                                                            name,
                                                            is_text,
                                                            relative));
                        if (is_text) {
                            text_file_cache.add (new Iide.FileEntry (
                                                                     path,
                                                                     name,
                                                                     true,
                                                                     relative));
                        }
                    }
                }
            }
        }
    }

    public Gee.List<Iide.FileEntry>? get_file_cache () {
        if (!cache_valid) {
            return null;
        }
        return file_cache;
    }

    public Gee.List<Iide.FileEntry>? get_text_file_cache () {
        if (!cache_valid) {
            return null;
        }
        return text_file_cache;
    }

    public async void ensure_file_cache_async () {
        if (cache_valid || cache_loading) {
            return;
        }
        yield rebuild_file_cache_async ();
    }

    public void invalidate_file_cache () {
        cache_valid = false;
        file_cache_invalidated ();
    }

    public string ? get_workspace_root_path () {
        if (current_project_root != null) {
            return current_project_root.get_path ();
        }
        return null;
    }

    public void open_project_by_path (string path) {
        if (path != null && path != "") {
            var file = GLib.File.new_for_path (path);
            if (file.query_exists (null)) {
                open_project_folder.begin (file);
            }
        }
    }

    public GLib.File? get_current_project_root () {
        return current_project_root;
    }

    public string ? get_current_project_name () {
        return current_project_name;
    }

    public bool has_open_project () {
        return current_project_root != null;
    }

    public async void open_project_dialog (Window parent_window) {
        var dialog = new FileDialog () {
            title = _("Open Project"),
            modal = true
        };

        var last_dir = settings.last_open_directory;
        if (last_dir != null && last_dir != "") {
            dialog.initial_folder = GLib.File.new_for_path (last_dir);
        }

        try {
            var file = yield dialog.select_folder (parent_window, null);

            if (file != null) {
                yield open_project_folder (file);
            }
        } catch {
            // User dismissed dialog or other error - silently ignore
        }
    }

    /**
     * АСИНХРОННОЕ ЗАКРЫТИЕ СЕРВЕРОВ (Вызывается из вашего нового метода Window.shutdown_all_running_lsp_servers_async)
     */
    public async void shutdown_all_running_lsp_servers_async () {
        if (!this.has_open_project ())
            return;
        
        LoggerService.get_instance ().info ("PROJECT", "Initiating LSP shutdown sequence via ProjectManager...");
        yield LspService.get_instance ().shutdown_all_running_lsp_servers_async ();
    }

    /**
     * Вспомогательный метод для получения абсолютного пути к файлу конфигурации внутри .iide/
     * Используется другими сервисами приложения
     */
    public string? get_project_config_file_path (string filename) {
        if (this.iide_dir == null)
            return null;
        return GLib.Path.build_filename (this.iide_dir.get_path (), filename);
    }

    private void restore_session_and_panels () {
        string? config_path = this.get_project_config_file_path ("workspace.json");
        if (config_path == null)
            return;
        
        var docs = new Gee.ArrayList<PanelLayoutHelper.DocumentInfo> ();
        PanelLayoutHelper.PanelsInfo? panels = null;
        
        var parser = new Json.Parser ();
        try {
            parser.load_from_file (config_path);
            var root = parser.get_root ().get_object ();
            var session = root.get_object_member ("session");

            if (session.has_member ("grid_layout")) {
                var grid_layout = session.get_object_member ("grid_layout");
                if (grid_layout.has_member ("documents")) {
                    var docs_array = grid_layout.get_array_member ("documents");
                    foreach (var node in docs_array.get_elements ()) {
                        var obj = node.get_object ();
                        var info = new PanelLayoutHelper.DocumentInfo ();
                        info.uri = obj.get_string_member ("uri");
                        info.column = obj.has_member ("column") ? (uint) obj.get_int_member ("column") : 0;
                        info.row = obj.has_member ("row") ? (uint) obj.get_int_member ("row") : 0;
                        docs.add (info);
                    }
                }
            }

            if (session.has_member ("dock_layout")) {
                var dock_layout = session.get_object_member ("dock_layout");
                panels = new PanelLayoutHelper.PanelsInfo ();
                panels.reveal_start = dock_layout.get_boolean_member ("reveal_start");
                panels.reveal_end = dock_layout.get_boolean_member ("reveal_end");
                panels.reveal_bottom = dock_layout.get_boolean_member ("reveal_bottom");
                panels.start_width = (int) dock_layout.get_int_member ("start_width");
                panels.end_width = (int) dock_layout.get_int_member ("end_width");
                panels.bottom_height = (int) dock_layout.get_int_member ("bottom_height");
                if (dock_layout.has_member ("widgets")) {
                    var widgets_array = dock_layout.get_array_member ("widgets");
                    foreach (var node in widgets_array.get_elements ()) {
                        var obj = node.get_object ();
                        var info = new PanelLayoutHelper.WidgetInfo ();
                        info.panel_id = obj.get_string_member ("panel_id");
                        info.area = (int) obj.get_int_member ("area");
                        info.column = (uint) obj.get_int_member ("column");
                        info.row = (uint) obj.get_int_member ("row");
                        info.depth = (uint) obj.get_int_member ("depth");
                        panels.widgets.set (info.panel_id, info);
                    }
                }
            }

        } catch (GLib.Error e) {
            LoggerService.get_instance ().error ("PROJECT", "Failed to read workspace.json: " + e.message);
            docs.clear ();
            panels = null;
        }

        // Восстанавливаем панели
        this.window.restore_documents_grid (docs);
    }

    /**
     * Сохранение текущей сессии и очистка Documents grid
     */
    public void save_documents_grid () {
        string? config_path = this.get_project_config_file_path ("workspace.json");
        if (config_path == null)
            return;

        var root = new Json.Object ();
        var session = new Json.Object ();
        session.set_object_member (
            "grid_layout",
            PanelLayoutHelper.grid_documents_to_json (this.window.grid).get_object ()
        );
        session.set_object_member (
            "dock_layout",
            PanelLayoutHelper.dock_to_json (this.window.dock).get_object ()
        );

        root.set_object_member ("session", session);

        var generator = new Json.Generator ();
        generator.set_pretty (true);
        var root_node = new Json.Node (Json.NodeType.OBJECT);
        root_node.set_object (root);
        generator.set_root (root_node);

        try {
            generator.to_file (config_path);
        } catch (GLib.Error e) {
            LoggerService.get_instance ().error ("PROJECT", "Failed to write workspace.json: " + e.message);
        }
    }

    public void save_session_and_clear_panels () {
        this.save_documents_grid ();

        // Выполняем очистку панелей
        this.window.clear_documents_grid ();
    }
}