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

    public Window (Gtk.Application app) { Object (application: app); }

    construct {
        // Header
        var header = new Adw.HeaderBar ();
        var menu_button = new Gtk.MenuButton ();
        menu_button.icon_name = "open-menu-symbolic";
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

        // Theme switcher
        var style_manager = Adw.StyleManager.get_default ();
        var theme_toggle = new Gtk.ToggleButton ();
        theme_toggle.active = style_manager.color_scheme == Adw.ColorScheme.FORCE_DARK;
        theme_toggle.icon_name = theme_toggle.active ? "weather-clear-night-symbolic" : "weather-clear-symbolic";
        theme_toggle.tooltip_text = theme_toggle.active ? "Switch to Light Theme" : "Switch to Dark Theme";
        theme_toggle.toggled.connect (() => {
            style_manager.color_scheme = theme_toggle.active ? Adw.ColorScheme.FORCE_DARK : Adw.ColorScheme.FORCE_LIGHT;
            theme_toggle.icon_name = theme_toggle.active ? "weather-clear-night-symbolic" : "weather-clear-symbolic";
            theme_toggle.tooltip_text = theme_toggle.active ? "Switch to Light Theme" : "Switch to Dark Theme";
        });
        header.pack_end (theme_toggle);
        style_manager.color_scheme = Adw.ColorScheme.FORCE_LIGHT;

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
        var folder_view = new Iide.FileTreeView (File.new_for_path ("/home/kai/Projects/iide"));
        panel_widget_left1.child = folder_view;
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

        // Handle file selection to open documents
        folder_view.notify["selected-file"].connect (() => {
            var item = folder_view.selected_file;
            if (item != null && !item.is_directory) {
                var text_view = new Iide.TextView (item.file);
                var center_panel = new Panel.Widget ();
                center_panel.title = item.name;
                center_panel.child = text_view;
                grid.add (center_panel);
                center_panel.raise ();
            }
        });
    }
}
