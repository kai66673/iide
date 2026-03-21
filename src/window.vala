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

    public Window (Gtk.Application app) { Object (application: app); }

    construct {
        document_manager = new Iide.DocumentManager ();
        document_manager.document_opened.connect ((widget) => {
            grid.add (widget);
            widget.raise ();
        });

        // Header
        var header = new Adw.HeaderBar ();
        var menu_button = new Gtk.MenuButton ();
        menu_button.icon_name = "open-menu-symbolic";

        var menu = new GLib.Menu ();
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
        var folder_view = new Iide.FileTreeView (File.new_for_path ("/home/kai/BAS/bcad-ws/packages"));
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
}
