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

public class Iide.LanguageConfig : GLib.Object {
    public string language_id { get; construct set; }
    public string[] server_command { get; construct set; }
    public string[] file_patterns { get; construct set; }

    public LanguageConfig (string language_id, string[] server_command, string[] file_patterns) {
        Object (
                language_id: language_id,
                server_command: server_command,
                file_patterns: file_patterns
        );
    }
}

public class Iide.ProjectManager : Object {
    private static ProjectManager? _instance;
    private GLib.File? current_project_root;
    private string? current_project_name;
    private Iide.SettingsService settings;
    private Gee.HashMap<string, LanguageConfig> language_configs;

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
        if (_instance == null) {
            _instance = new ProjectManager ();
        }
        return _instance;
    }

    public ProjectManager () {
        current_project_root = null;
        current_project_name = null;
        settings = Iide.SettingsService.get_instance ();
        language_configs = new Gee.HashMap<string, LanguageConfig> ();
        file_cache = new Gee.ArrayList<Iide.FileEntry> ();
        text_file_cache = new Gee.ArrayList<Iide.FileEntry> ();
        init_default_language_configs ();
    }

    private void init_default_language_configs () {
        language_configs.set ("c", new LanguageConfig ("c", { "clangd" }, { "*.c", "*.h" }));
        language_configs.set ("cpp", new LanguageConfig ("cpp", { "clangd" }, { "*.cpp", "*.cc", "*.cxx", "*.hpp", "*.hxx", "*.h" }));
        language_configs.set ("python", new LanguageConfig ("python", { "basedpyright-langserver", "--stdio" }, { "*.py" }));
        language_configs.set ("rust", new LanguageConfig ("rust", { "rust-analyzer" }, { "*.rs" }));
        language_configs.set ("go", new LanguageConfig ("go", { "gopls" }, { "*.go" }));
        language_configs.set ("typescript", new LanguageConfig ("typescript", { "typescript-language-server", "--stdio" }, { "*.ts", "*.tsx" }));
        language_configs.set ("javascript", new LanguageConfig ("javascript", { "typescript-language-server", "--stdio" }, { "*.js", "*.jsx" }));
        language_configs.set ("json", new LanguageConfig ("json", { "vscode-json-languageserver", "--stdio" }, { "*.json" }));
        language_configs.set ("html", new LanguageConfig ("html", { "vscode-html-language-server", "--stdio" }, { "*.html", "*.htm" }));
        language_configs.set ("css", new LanguageConfig ("css", { "vscode-css-language-server", "--stdio" }, { "*.css", "*.scss", "*.less" }));
    }

    private string? last_loaded_config_path;

    public Gee.Collection<LanguageConfig> get_language_configs () {
        return language_configs.values;
    }

    public LanguageConfig ? get_language_config (string language_id) {
        return language_configs.get (language_id);
    }

    public void load_lsp_config (GLib.File project_root) {
        string? config_path = project_root.get_path ();
        if (config_path == null) {
            config_path = project_root.get_uri ();
        }

        if (config_path != null && config_path == last_loaded_config_path) {
            return;
        }

        init_default_language_configs ();

        var config_dir = project_root.get_child (".iide");
        var lsp_file = config_dir.get_child ("lsp.json");

        if (!lsp_file.query_exists (null)) {
            message ("No .iide/lsp.json found at %s", lsp_file.get_path ());
            last_loaded_config_path = config_path;
            return;
        }

        try {
            var parser = new Json.Parser ();
            parser.load_from_file (lsp_file.get_path ());
            var root = parser.get_root ();
            var obj = (Json.Object) root;

            if (obj.has_member ("languages")) {
                var languages = obj.get_array_member ("languages");
                int lang_count = (int) languages.get_length ();
                for (int j = 0; j < lang_count; j++) {
                    var node = languages.get_element (j);
                    var lang_obj = node.get_object ();
                    if (lang_obj == null)continue;

                    string? lang_id = null;
                    string[] ? server_cmd = null;
                    string[] ? patterns = null;

                    if (lang_obj.has_member ("id")) {
                        lang_id = lang_obj.get_string_member ("id");
                    }
                    if (lang_obj.has_member ("server")) {
                        var server_arr = lang_obj.get_array_member ("server");
                        int server_count = (int) server_arr.get_length ();
                        server_cmd = new string[server_count];
                        for (int i = 0; i < server_count; i++) {
                            server_cmd[i] = server_arr.get_string_element (i);
                        }
                    }
                    if (lang_obj.has_member ("patterns")) {
                        var patterns_arr = lang_obj.get_array_member ("patterns");
                        int patterns_count = (int) patterns_arr.get_length ();
                        patterns = new string[patterns_count];
                        for (int i = 0; i < patterns_count; i++) {
                            patterns[i] = patterns_arr.get_string_element (i);
                        }
                    }

                    if (lang_id != null) {
                        merge_language_config (lang_id, server_cmd, patterns);
                    }
                }
            }

            message ("Loaded LSP config from %s", lsp_file.get_path ());
            last_loaded_config_path = config_path;
        } catch (Error e) {
            warning ("Failed to load LSP config: %s", e.message);
        }
    }

    private void merge_language_config (string lang_id, string[]? server_cmd, string[]? patterns) {
        var config = language_configs.get (lang_id);
        if (config != null) {
            if (server_cmd != null && server_cmd.length > 0) {
                config.server_command = server_cmd;
            }
            if (patterns != null && patterns.length > 0) {
                config.file_patterns = patterns;
            }
            message ("Merged LSP config for '%s'", lang_id);
            return;
        }

        if (server_cmd != null && patterns != null) {
            language_configs.set (lang_id, new LanguageConfig (lang_id, server_cmd, patterns));
            message ("Added new LSP config for '%s'", lang_id);
        }
    }

    public async void open_project_async (GLib.File project_root) {
        if (!project_root.query_exists (null)) {
            stderr.printf ("Project directory does not exist: %s\n", project_root.get_path ());
            return;
        }

        if (current_project_root != null) {
            close_project ();
        }

        init_default_language_configs ();

        current_project_root = project_root;
        current_project_name = project_root.get_basename ();

        settings.current_project_path = project_root.get_path ();
        settings.add_recent_project (project_root.get_path ());
        settings.last_open_directory = project_root.get_parent ().get_path ();

        load_lsp_config (project_root);

        yield rebuild_file_cache_async ();

        setup_directory_monitor (project_root);

        project_opened (project_root);
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

    public void close_project () {
        if (directory_monitor != null) {
            directory_monitor.cancel ();
            directory_monitor = null;
        }

        if (current_project_root != null) {
            current_project_root = null;
            current_project_name = null;
            cache_valid = false;
            file_cache.clear ();
            text_file_cache.clear ();
            settings.current_project_path = "";
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
                open_project_async.begin (file);
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
                yield open_project_async (file);
            }
        } catch {
            // User dismissed dialog or other error - silently ignore
        }
    }
}