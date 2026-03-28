using Gtk;
using GLib;

public class Iide.ProjectManager : Object {
    private GLib.File? current_project_root;
    private string? current_project_name;
    private Iide.SettingsService settings;

    public signal void project_opened (GLib.File project_root);
    public signal void project_closed ();

    public ProjectManager () {
        current_project_root = null;
        current_project_name = null;
        settings = Iide.SettingsService.get_instance ();
    }

    public async void open_project_async (GLib.File project_root) {
        if (!project_root.query_exists (null)) {
            stderr.printf ("Project directory does not exist: %s\n", project_root.get_path ());
            return;
        }

        if (current_project_root != null) {
            close_project ();
        }

        current_project_root = project_root;
        current_project_name = project_root.get_basename ();

        settings.current_project_path = project_root.get_path ();
        settings.add_recent_project (project_root.get_path ());
        settings.last_open_directory = project_root.get_parent ().get_path ();

        project_opened (project_root);
    }

    public void close_project () {
        if (current_project_root != null) {
            current_project_root = null;
            current_project_name = null;
            settings.current_project_path = "";
            project_closed ();
        }
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

    public string? get_current_project_name () {
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
