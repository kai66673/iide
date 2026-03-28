/* window.vala
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

using Gtk;
using Adw;
using Panel;

public class Iide.Window : Panel.DocumentWorkspace {

    private Iide.DocumentManager document_manager;
    private Iide.ProjectManager project_manager;
    private Application app;
    private Adw.HeaderBar header;

    public Window (Application app) {
        Object (application: app);

        // Загрузка состояния окна
        int width, height;
        bool is_maximized;
        if (app == null) {
            message ("app is null");
        }
        app.settings_manager.load_window_state (out width, out height, out is_maximized);

        this.set_default_size (width, height);
        if (is_maximized) {
            this.maximize ();
        }

        // Theme switcher
        var style_manager = Adw.StyleManager.get_default ();
        var theme_toggle = new Gtk.ToggleButton ();

        // Загрузка сохраненной темы
        var saved_theme = app.settings_manager.load_theme ();
        theme_toggle.active = saved_theme == "dark";
        style_manager.color_scheme = theme_toggle.active ? Adw.ColorScheme.FORCE_DARK : Adw.ColorScheme.FORCE_LIGHT;

        theme_toggle.icon_name = theme_toggle.active ? "weather-clear-night-symbolic" : "weather-clear-symbolic";
        theme_toggle.tooltip_text = theme_toggle.active ? "Switch to Light Theme" : "Switch to Dark Theme";
        var app_ref = (Iide.Application) this.get_application ();
        theme_toggle.toggled.connect (() => {
            style_manager.color_scheme = theme_toggle.active ? Adw.ColorScheme.FORCE_DARK : Adw.ColorScheme.FORCE_LIGHT;
            theme_toggle.icon_name = theme_toggle.active ? "weather-clear-night-symbolic" : "weather-clear-symbolic";
            theme_toggle.tooltip_text = theme_toggle.active ? "Switch to Light Theme" : "Switch to Dark Theme";

            // Сохранение темы
            app_ref.settings_manager.save_theme (theme_toggle.active ? "dark" : "light");
        });
        header.pack_end (theme_toggle);
    }

    construct {
        document_manager = new Iide.DocumentManager ();
        project_manager = new Iide.ProjectManager ();

        // Сохранение состояния окна при закрытии
        this.close_request.connect (() => {
            app.settings_manager.save_window_state (this.get_width (), this.get_height (), this.is_maximized ());
            return false;
        });
        document_manager.document_opened.connect ((widget) => {
            grid.add (widget);
            widget.raise ();
            widget.view_grab_focus ();
        });

        // Header
        header = new Adw.HeaderBar ();
        var menu_button = new Gtk.MenuButton ();
        menu_button.icon_name = "open-menu-symbolic";

        var menu = new GLib.Menu ();
        menu.append (_("Open Project"), "app.open_project");
        menu.append (_("Save All"), "app.save");
        menu.append (_("Preferences"), "app.preferences");
        menu.append (_("About"), "app.about");
        menu.append (_("Quit"), "app.quit");
        menu_button.set_menu_model (menu);

        header.pack_end (menu_button);

        dock.reveal_start = true;
        dock.start_width = 200;
        var start_toggle_btn = new Panel.ToggleButton (dock, Panel.Area.START);
        header.pack_start (start_toggle_btn);

        dock.reveal_end = false;
        dock.end_width = 200;
        var end_toggle_btn = new Panel.ToggleButton (dock, Panel.Area.END);
        header.pack_end (end_toggle_btn);

        set_titlebar (header);

        // statusbar
        dock.reveal_bottom = false;
        dock.bottom_height = 200;
        var bottom_toggle_btn = new Panel.ToggleButton (dock, Panel.Area.BOTTOM);
        statusbar.add_suffix (1, bottom_toggle_btn);

        var panel_area_left = new Panel.Position ();
        panel_area_left.area = Panel.Area.START;

        var panel_widget_left1 = new Panel.Widget ();
        panel_widget_left1.title = "Project Tree";
        panel_widget_left1.icon_name = "folder-symbolic";

        // Создаем FileTreeView без начального пути
        var folder_view = new Iide.FileTreeView (null);
        panel_widget_left1.child = folder_view;

        // Подключаем сигналы менеджера проекта
        project_manager.project_opened.connect ((project_root) => {
            folder_view.set_root_file (project_root);
        });

        project_manager.project_closed.connect (() => {
            folder_view.set_root_file (null);
        });
        panel_widget_left1.can_maximize = true;

        var panel_widget_left2 = new Panel.Widget ();
        panel_widget_left2.title = "LEFT 2";
        panel_widget_left2.icon_name = "folder-symbolic";
        panel_widget_left2.child = new Gtk.Label ("LEFT 2");
        panel_widget_left2.can_maximize = true;

        var panel_area_bottom = new Panel.Position ();
        panel_area_bottom.area = Panel.Area.BOTTOM;

        var panel_widget_bottom = new Panel.Widget ();
        panel_widget_bottom.title = "BOTTOM";
        panel_widget_bottom.icon_name = "folder-symbolic";
        panel_widget_bottom.child = new Iide.Terminal ();
        panel_widget_bottom.can_maximize = true;

        var panel_area_right = new Panel.Position ();
        panel_area_right.area = Panel.Area.END;

        var panel_widget_right = new Panel.Widget ();
        panel_widget_right.title = "RIGHT";
        panel_widget_right.icon_name = "folder-symbolic";
        panel_widget_right.child = new Gtk.Label ("RIGHT");
        panel_widget_right.can_maximize = true;

        add_widget (panel_widget_left1, panel_area_left);
        add_widget (panel_widget_left2, panel_area_left);
        add_widget (panel_widget_right, panel_area_right);
        add_widget (panel_widget_bottom, panel_area_bottom);

        // Handle file activation to open documents
        folder_view.file_activated.connect ((item) => {
            if (!item.is_directory) {
                document_manager.open_document (item.file, this);
            }
        });

        // Handle window close
        this.close_request.connect (() => {
            bool has_unsaved = false;
            foreach (var entry in document_manager.documents.entries) {
                if (entry.value is Iide.TextView) {
                    var tv = (Iide.TextView) entry.value;
                    if (tv.is_modified) {
                        has_unsaved = true;
                        break;
                    }
                }
            }
            if (has_unsaved) {
                var dialog = new Adw.AlertDialog (_("Unsaved Changes"), _("You have unsaved documents. Save before closing?"));
                dialog.add_response ("cancel", _("Cancel"));
                dialog.add_response ("discard", _("Discard"));
                dialog.add_response ("save", _("Save"));
                dialog.set_response_appearance ("save", Adw.ResponseAppearance.SUGGESTED);
                dialog.response.connect ((response) => {
                    if (response == "save") {
                        foreach (var entry in document_manager.documents.entries) {
                            if (entry.value is Iide.TextView) {
                                var tv = (Iide.TextView) entry.value;
                                if (tv.is_modified) {
                                    tv.save ();
                                }
                            }
                        }
                        this.destroy ();
                    } else if (response == "discard") {
                        this.destroy ();
                    }
                    // cancel does nothing
                });
                dialog.present (this);
                return true;
            }
            return false;
        });
    }

    public void save_modified () {
        foreach (var uri in document_manager.documents.keys) {
            var widget = document_manager.documents[uri];
            if (widget is Iide.TextView) {
                var tv = widget as Iide.TextView;
                if (tv.is_modified) {
                    tv.save ();
                }
            }
        }
    }

    public void open_project_dialog () {
        project_manager.open_project_dialog (this);
    }
}
