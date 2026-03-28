using GLib;

public class Iide.SettingsManager : Object {
    private GLib.Settings settings;
    private string schema_id = "org.github.kai66673.iide";

    public SettingsManager () {
        try {
            settings = new GLib.Settings (schema_id);
            if (settings == null) {
                warning ("Settings object is null");
            } else {
                message ("Settings initialized successfully");
            }
        } catch (Error e) {
            warning ("Failed to create settings: %s", e.message);
            settings = null;
        }
    }

    public void save_window_state (int width, int height, bool is_maximized) {
        if (settings == null)return;

        settings.set_int ("window-width", width);
        settings.set_int ("window-height", height);
        settings.set_boolean ("window-maximized", is_maximized);
    }

    public void load_window_state (out int width, out int height, out bool is_maximized) {
        if (settings == null) {
            width = 1200;
            height = 800;
            is_maximized = false;
            return;
        }

        width = settings.get_int ("window-width");
        height = settings.get_int ("window-height");
        is_maximized = settings.get_boolean ("window-maximized");
    }

    public void save_theme (string theme) {
        if (settings == null)return;
        settings.set_string ("theme", theme);
    }

    public string load_theme () {
        if (settings == null)return "light";
        return settings.get_string ("theme");
    }

    public void save_recent_projects (string[] projects) {
        if (settings == null)return;
        settings.set_strv ("recent-projects", projects);
    }

    public string[] load_recent_projects () {
        if (settings == null)return new string[0];
        return settings.get_strv ("recent-projects");
    }

    public void add_recent_project (string project_path) {
        if (settings == null)return;

        var projects = load_recent_projects ();
        var new_projects = new string[projects.length + 1];
        bool found = false;
        int new_index = 0;

        // Добавляем проект в начало, если его нет в списке
        new_projects[0] = project_path;
        new_index = 1;

        for (int i = 0; i < projects.length; i++) {
            if (projects[i] != project_path) {
                new_projects[new_index] = projects[i];
                new_index++;
            }
        }

        // Сохраняем не более 5 проектов
        if (new_index > 5) {
            new_index = 5;
        }

        var final_projects = new string[new_index];
        for (int i = 0; i < new_index; i++) {
            final_projects[i] = new_projects[i];
        }

        save_recent_projects (final_projects);
    }
}
