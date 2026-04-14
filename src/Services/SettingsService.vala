/*
 * settingsservice.vala
 *
 * Copyright 2026 kai
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

public enum ColorScheme {
    SYSTEM,
    LIGHT,
    DARK;

    public static ColorScheme from_string (string value) {
        switch (value) {
        case "light":
            return LIGHT;
        case "dark":
            return DARK;
        default:
            return SYSTEM;
        }
    }

    public string to_string () {
        switch (this) {
        case LIGHT:
            return "light";
        case DARK:
            return "dark";
        default:
            return "system";
        }
    }

    public Adw.ColorScheme to_adw_color_scheme () {
        switch (this) {
        case LIGHT:
            return Adw.ColorScheme.FORCE_LIGHT;
        case DARK:
            return Adw.ColorScheme.FORCE_DARK;
        default:
            return Adw.ColorScheme.DEFAULT;
        }
    }
}

public class FontSizeHelper : Object {
    public const int DEFAULT_ZOOM_LEVEL = 6;
    public const int MIN_ZOOM_LEVEL = 1;
    public const int MAX_ZOOM_LEVEL = 15;
    private const int[] FONT_SIZES = { 4, 6, 8, 10, 12, 14, 16, 18, 20, 24, 28, 32, 36, 40, 48 };

    public static int get_size_for_zoom_level (int zoom_level) {
        if (zoom_level >= MIN_ZOOM_LEVEL && zoom_level <= MAX_ZOOM_LEVEL) {
            return FONT_SIZES[zoom_level - 1];
        }
        return FONT_SIZES[DEFAULT_ZOOM_LEVEL - 1];
    }

    public static int[] get_available_sizes () {
        return FONT_SIZES;
    }
}

public class Iide.SettingsService : Object {
    private static SettingsService? _instance;
    private Settings settings;

    public signal void editor_setting_changed (string key);

    public static SettingsService get_instance () {
        if (_instance == null) {
            _instance = new SettingsService ();
        }
        return _instance;
    }

    private SettingsService () {
        settings = new Settings ("org.github.kai66673.iide");
    }

    public ColorScheme color_scheme {
        get {
            return ColorScheme.from_string (settings.get_string ("color-scheme"));
        }
        set {
            settings.set_string ("color-scheme", value.to_string ());
            editor_setting_changed ("color-scheme");
        }
    }

    public int editor_font_size {
        get {
            return (int) settings.get_double ("editor-font-size");
        }
        set {
            settings.set_double ("editor-font-size", (double) value);
            editor_setting_changed ("editor-font-size");
        }
    }

    public bool show_minimap {
        get {
            return settings.get_boolean ("show-minimap");
        }
        set {
            settings.set_boolean ("show-minimap", value);
            editor_setting_changed ("show-minimap");
        }
    }

    public bool show_line_numbers {
        get {
            return settings.get_boolean ("show-line-numbers");
        }
        set {
            settings.set_boolean ("show-line-numbers", value);
            editor_setting_changed ("show-line-numbers");
        }
    }

    public bool highlight_current_line {
        get {
            return settings.get_boolean ("highlight-current-line");
        }
        set {
            settings.set_boolean ("highlight-current-line", value);
            editor_setting_changed ("highlight-current-line");
        }
    }

    public bool auto_indent {
        get {
            return settings.get_boolean ("auto-indent");
        }
        set {
            settings.set_boolean ("auto-indent", value);
            editor_setting_changed ("auto-indent");
        }
    }

    public int panel_start_width {
        get {
            return (int) settings.get_double ("panel-start-width");
        }
        set {
            settings.set_double ("panel-start-width", (double) value);
        }
    }

    public int panel_end_width {
        get {
            return (int) settings.get_double ("panel-end-width");
        }
        set {
            settings.set_double ("panel-end-width", (double) value);
        }
    }

    public int panel_bottom_height {
        get {
            return (int) settings.get_double ("panel-bottom-height");
        }
        set {
            settings.set_double ("panel-bottom-height", (double) value);
        }
    }

    public int panel_bottom_width {
        get {
            return (int) settings.get_double ("panel-bottom-width");
        }
        set {
            settings.set_double ("panel-bottom-width", (double) value);
        }
    }

    public bool reveal_start_panel {
        get {
            return settings.get_boolean ("reveal-start-panel");
        }
        set {
            settings.set_boolean ("reveal-start-panel", value);
        }
    }

    public bool reveal_end_panel {
        get {
            return settings.get_boolean ("reveal-end-panel");
        }
        set {
            settings.set_boolean ("reveal-end-panel", value);
        }
    }

    public bool reveal_bottom_panel {
        get {
            return settings.get_boolean ("reveal-bottom-panel");
        }
        set {
            settings.set_boolean ("reveal-bottom-panel", value);
        }
    }

    public string[] recent_projects {
        owned get {
            return settings.get_strv ("recent-projects");
        }
    }

    public int max_recent_projects {
        get {
            return (int) settings.get_double ("max-recent-projects");
        }
        set {
            settings.set_double ("max-recent-projects", (double) value);
        }
    }

    public string last_open_directory {
        owned get {
            return settings.get_string ("last-open-directory");
        }
        set {
            settings.set_string ("last-open-directory", value);
        }
    }

    public string current_project_path {
        owned get {
            return settings.get_string ("current-project-path");
        }
        set {
            settings.set_string ("current-project-path", value);
        }
    }

    public Gee.ArrayList<string> open_documents {
        owned get {
            var arr = settings.get_strv ("open-documents");
            var list = new Gee.ArrayList<string> ();
            foreach (var s in arr) {
                list.add (s);
            }
            return (owned) list;
        }
        set {
            var arr = new string[value.size];
            int i = 0;
            foreach (var s in value) {
                arr[i++] = s;
            }
            settings.set_strv ("open-documents", arr);
        }
    }

    public string panel_layout {
        owned get {
            return settings.get_string ("panel-layout");
        }
        set {
            settings.set_string ("panel-layout", value);
        }
    }

    public string grid_layout {
        owned get {
            return settings.get_string ("grid-layout");
        }
        set {
            settings.set_string ("grid-layout", value);
            Settings.sync ();
        }
    }

    public int window_width {
        get {
            return (int) settings.get_double ("window-width");
        }
        set {
            settings.set_double ("window-width", (double) value);
        }
    }

    public int window_height {
        get {
            return (int) settings.get_double ("window-height");
        }
        set {
            settings.set_double ("window-height", (double) value);
        }
    }

    public bool window_maximized {
        get {
            return settings.get_boolean ("window-maximized");
        }
        set {
            settings.set_boolean ("window-maximized", value);
        }
    }

    public void add_recent_project (string path) {
        var projects = new List<string> ();
        projects.prepend (path);

        foreach (var p in recent_projects) {
            if (p != path) {
                bool found = false;
                foreach (var existing in projects) {
                    if (existing == path) {
                        found = true;
                        break;
                    }
                }
                if (!found) {
                    projects.append (p);
                }
            }
        }

        var arr = new string[projects.length ()];
        int i = 0;
        foreach (var p in projects) {
            arr[i++] = p;
        }
        settings.set_strv ("recent-projects", arr);
    }

    public void remove_recent_project (string path) {
        var projects = new List<string> ();
        foreach (var p in recent_projects) {
            if (p != path) {
                projects.append (p);
            }
        }

        var arr = new string[projects.length ()];
        int i = 0;
        foreach (var p in projects) {
            arr[i++] = p;
        }
        settings.set_strv ("recent-projects", arr);
    }

    public void clear_recent_projects () {
        settings.set_strv ("recent-projects", {});
    }

    public signal void setting_changed (string key);
}
