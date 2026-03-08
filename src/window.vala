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

[GtkTemplate (ui = "/org/github/kai66673/iide/window.ui")]
public class Iide.Window : Panel.DocumentWorkspace {
    [GtkChild] private unowned Panel.Paned start_area;
    [GtkChild] private unowned Panel.Paned end_area;
    [GtkChild] private unowned Adw.WindowTitle window_title;

    public Window (Gtk.Application app) {
        Object (application: app);
    }

    construct {
        window_title.title = "APP";

        end_area.orientation = Gtk.Orientation.HORIZONTAL;
        var end_frame = new Panel.Frame ();
        end_frame.orientation = Gtk.Orientation.HORIZONTAL;
        end_area.append (end_frame);

        var end_widget = new Panel.Widget();
        end_widget.title = "Dynamic";
        end_widget.icon_name = "folder-symbolic";
        end_widget.vexpand = true;
        end_widget.can_maximize = true;
        end_frame.add (end_widget);
        var xxx_lalab = new Gtk.Label("A and B");
        end_widget.child = xxx_lalab;

        var end_widget1 = new Panel.Widget();
        end_widget1.title = "<<Dynamic>>";
        end_widget1.icon_name = "folder-symbolic";
        end_widget1.vexpand = true;
        end_widget1.can_maximize = true;
        end_frame.add (end_widget1);
        var dyn_lalab = new Gtk.Label("Test Content");
        end_widget1.child = dyn_lalab;

        var top_position = new Panel.Position();
        top_position.area = Panel.Area.TOP;
        top_position.column = 0;
        top_position.row = 0;
        var top_frame = dock.create_frame (top_position);
        var end_widget2 = new Panel.Widget();
        end_widget2.title = "<<TOP>>";
        end_widget2.icon_name = "folder-symbolic";
        end_widget2.vexpand = true;
        top_frame.add (end_widget2);

/*
        // Header
        var view = new Adw.ToolbarView();
        content = view;

        var header = new Adw.HeaderBar();
        var menu_button = new Gtk.MenuButton();
        menu_button.icon_name = "open-menu-symbolic";
        header.pack_end(menu_button);

        // Header-menu
        var menu = new GLib.Menu();
        menu.append_item(new GLib.MenuItem(_("_Preferences"), "app.preferences"));
        menu.append_item(new GLib.MenuItem(_("_About"), "app.about"));

        menu_button.menu_model = menu;

        view.add_top_bar(header);

        dock.reveal_start = true;
        dock.reveal_end = true;
        dock.reveal_bottom = true;
        dock.reveal_top = false;

        var panel_area_left = new Panel.Position();
        panel_area_left.area = Panel.Area.START;

        var panel_widget = new Panel.Widget();
        panel_widget.child = new Gtk.Label("LEFT");

        add_widget(panel_widget, panel_area_left);
        */

       start_area.hexpand = true;
    }
}
