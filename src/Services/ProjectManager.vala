using Gtk;

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
        try {
            if (!project_root.query_exists (null)) {
                stderr.printf ("Project directory does not exist: %s\n", project_root.get_path ());
                return;
            }

            if (current_project_root != null) {
                close_project ();
            }

            current_project_root = project_root;
            current_project_name = project_root.get_basename ();

            settings.add_recent_project (project_root.get_path ());
            settings.last_open_directory = project_root.get_parent ().get_path ();

            project_opened (project_root);
        } catch (Error e) {
            stderr.printf ("Error opening project: %s\n", e.message);
        }
    }

    public void close_project () {
        if (current_project_root != null) {
            current_project_root = null;
            current_project_name = null;
            project_closed ();
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
        var dialog = new Gtk.FileChooserNative (
                                                "Open Project",
                                                parent_window,
                                                Gtk.FileChooserAction.SELECT_FOLDER,
                                                "_Open",
                                                "_Cancel"
        );

        dialog.modal = true;
        dialog.transient_for = parent_window;

        var last_dir = settings.last_open_directory;
        if (last_dir != null && last_dir != "") {
            dialog.set_current_folder (GLib.File.new_for_path (last_dir));
        }

        dialog.response.connect ((response) => {
            if (response == Gtk.ResponseType.ACCEPT) {
                var file = dialog.get_file ();
                if (file != null) {
                    open_project_async (file);
                }
            }
        });

        dialog.show ();
    }
}
