/*
 * preferencesdialog.vala
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

public class Iide.PreferencesDialog : Adw.PreferencesWindow {
    private Iide.SettingsService settings;
    private Adw.StyleManager style_manager;

    private Adw.ComboRow color_scheme_row;
    private Adw.SwitchRow show_minimap_row;
    private Adw.SwitchRow show_line_numbers_row;
    private Adw.SwitchRow highlight_current_line_row;
    private Adw.SwitchRow auto_indent_row;

    public PreferencesDialog () {
        Object (modal: true, destroy_with_parent: true);
        settings = Iide.SettingsService.get_instance ();
        style_manager = Adw.StyleManager.get_default ();

        title = _("Preferences");
        set_default_size (500, 450);

        build_ui ();
    }

    private void build_ui () {
        var appearance_page = new Adw.PreferencesPage () {
            title = _("Appearance"),
            icon_name = "preferences-desktop-appearance-symbolic"
        };

        var appearance_group = new Adw.PreferencesGroup () {
            title = _("Appearance")
        };

        color_scheme_row = new Adw.ComboRow () {
            title = _("Color Scheme"),
            model = new Gtk.StringList ({"System", "Light", "Dark"})
        };
        var scheme_index = settings.color_scheme;
        color_scheme_row.selected = (uint) scheme_index;
        color_scheme_row.notify["selected"].connect (() => {
            var scheme = (ColorScheme) color_scheme_row.selected;
            settings.color_scheme = scheme;
            style_manager.color_scheme = scheme.to_adw_color_scheme ();
        });
        appearance_group.add (color_scheme_row);
        appearance_page.add (appearance_group);

        var editor_page = new Adw.PreferencesPage () {
            title = _("Editor"),
            icon_name = "accessories-text-editor-symbolic"
        };

        var editor_group = new Adw.PreferencesGroup () {
            title = _("Editor")
        };

        show_minimap_row = new Adw.SwitchRow () {
            title = _("Show Minimap"),
            subtitle = _("Display a minimap showing the document overview")
        };
        show_minimap_row.active = settings.show_minimap;
        show_minimap_row.notify["active"].connect (() => {
            settings.show_minimap = show_minimap_row.active;
        });
        editor_group.add (show_minimap_row);

        show_line_numbers_row = new Adw.SwitchRow () {
            title = _("Show Line Numbers"),
            subtitle = _("Display line numbers on the editor gutter")
        };
        show_line_numbers_row.active = settings.show_line_numbers;
        show_line_numbers_row.notify["active"].connect (() => {
            settings.show_line_numbers = show_line_numbers_row.active;
        });
        editor_group.add (show_line_numbers_row);

        highlight_current_line_row = new Adw.SwitchRow () {
            title = _("Highlight Current Line"),
            subtitle = _("Highlight the line where the cursor is positioned")
        };
        highlight_current_line_row.active = settings.highlight_current_line;
        highlight_current_line_row.notify["active"].connect (() => {
            settings.highlight_current_line = highlight_current_line_row.active;
        });
        editor_group.add (highlight_current_line_row);

        auto_indent_row = new Adw.SwitchRow () {
            title = _("Auto Indent"),
            subtitle = _("Automatically indent new lines based on the previous line")
        };
        auto_indent_row.active = settings.auto_indent;
        auto_indent_row.notify["active"].connect (() => {
            settings.auto_indent = auto_indent_row.active;
        });
        editor_group.add (auto_indent_row);
        editor_page.add (editor_group);

        var projects_page = new Adw.PreferencesPage () {
            title = _("Projects"),
            icon_name = "folder-open-symbolic"
        };

        var projects_group = new Adw.PreferencesGroup () {
            title = _("Projects")
        };

        var recent_projects_row = new Adw.ActionRow () {
            title = _("Recent Projects")
        };
        var recent_projects = settings.recent_projects;
        if (recent_projects.length > 0) {
            var subtitle = string.joinv ("\n", recent_projects);
            recent_projects_row.subtitle = subtitle;
        } else {
            recent_projects_row.subtitle = _("No recent projects");
        }
        var clear_button = new Gtk.Button () {
            icon_name = "edit-clear-symbolic",
            tooltip_text = _("Clear Recent Projects")
        };
        clear_button.clicked.connect (() => {
            settings.clear_recent_projects ();
            recent_projects_row.subtitle = _("No recent projects");
        });
        recent_projects_row.add_suffix (clear_button);
        recent_projects_row.activatable_widget = clear_button;
        projects_group.add (recent_projects_row);
        projects_page.add (projects_group);

        add (appearance_page);
        add (editor_page);
        add (projects_page);
    }
}
