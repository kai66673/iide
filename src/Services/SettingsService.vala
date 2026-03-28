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

public class Iide.SettingsService : Object {
    private static SettingsService? _instance;
    private Settings settings;

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
        }
    }

    public double editor_font_size {
        get {
            return settings.get_double ("editor-font-size");
        }
        set {
            settings.set_double ("editor-font-size", value);
        }
    }

    public bool show_minimap {
        get {
            return settings.get_boolean ("show-minimap");
        }
        set {
            settings.set_boolean ("show-minimap", value);
        }
    }

    public bool show_line_numbers {
        get {
            return settings.get_boolean ("show-line-numbers");
        }
        set {
            settings.set_boolean ("show-line-numbers", value);
        }
    }

    public bool highlight_current_line {
        get {
            return settings.get_boolean ("highlight-current-line");
        }
        set {
            settings.set_boolean ("highlight-current-line", value);
        }
    }

    public bool auto_indent {
        get {
            return settings.get_boolean ("auto-indent");
        }
        set {
            settings.set_boolean ("auto-indent", value);
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
        var projects = new Gee.ArrayList<string> ();
        projects.add (path);

        foreach (var p in recent_projects) {
            if (p != path && projects.size < max_recent_projects) {
                projects.add (p);
            }
        }

        settings.set_strv ("recent-projects", projects.to_array ());
    }

    public void remove_recent_project (string path) {
        var projects = new Gee.ArrayList<string> ();
        foreach (var p in recent_projects) {
            if (p != path) {
                projects.add (p);
            }
        }
        settings.set_strv ("recent-projects", projects.to_array ());
    }

    public void clear_recent_projects () {
        settings.set_strv ("recent-projects", {});
    }

    public signal void setting_changed (string key);
}
