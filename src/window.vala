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
    private Iide.SettingsService settings;

    public Window (Gtk.Application app) { Object (application: app); }

    construct {
        settings = Iide.SettingsService.get_instance ();
        document_manager = new Iide.DocumentManager ();
        project_manager = new Iide.ProjectManager ();
        document_manager.document_opened.connect ((widget) => {
            grid.add (widget);
            widget.raise ();
            widget.view_grab_focus ();
        });

        // Header
        var header = new Adw.HeaderBar ();
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

        var panel_layout = settings.panel_layout;
        if (panel_layout != null && panel_layout != "") {
            Iide.PanelLayoutHelper.deserialize_dock (panel_layout, dock);
        } else {
            dock.reveal_start = settings.reveal_start_panel;
            dock.start_width = settings.panel_start_width;
            dock.reveal_end = settings.reveal_end_panel;
            dock.end_width = settings.panel_end_width;
            dock.reveal_bottom = settings.reveal_bottom_panel;
            dock.bottom_height = settings.panel_bottom_height;
        }
        var start_toggle_btn = new Panel.ToggleButton (dock, Panel.Area.START);
        header.pack_start (start_toggle_btn);

        var end_toggle_btn = new Panel.ToggleButton (dock, Panel.Area.END);
        header.pack_end (end_toggle_btn);

        set_titlebar (header);

        // Theme switcher
        var style_manager = Adw.StyleManager.get_default ();
        style_manager.color_scheme = settings.color_scheme.to_adw_color_scheme ();

        var theme_list = new Gtk.StringList ({"System", "Light", "Dark"});
        var expr = new Gtk.PropertyExpression (typeof (Gtk.StringObject), null, "string");
        var theme_dropdown = new Gtk.DropDown (theme_list, expr) {
            selected = (uint) settings.color_scheme,
            tooltip_text = _("Color Scheme"),
            show_arrow = false
        };

        var factory = new Gtk.SignalListItemFactory ();
        factory.setup.connect ((item) => {
            var list_item = item as Gtk.ListItem;
            var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            var icon = new Gtk.Image ();
            var label = new Gtk.Label (null);
            label.xalign = 0;
            box.append (icon);
            box.append (label);
            list_item.set_child (box);
        });
        factory.bind.connect ((item) => {
            var list_item = item as Gtk.ListItem;
            var box = list_item.get_child () as Gtk.Box;
            var icon = box.get_first_child () as Gtk.Image;
            var label = icon.get_next_sibling () as Gtk.Label;
            var obj = list_item.get_item () as Gtk.StringObject;
            var text = obj.get_string ();
            label.set_label (text);

            string icon_name;
            switch (text) {
                case "System":
                    icon_name = "weather-overcast-symbolic";
                    break;
                case "Light":
                    icon_name = "weather-clear-symbolic";
                    break;
                case "Dark":
                    icon_name = "weather-clear-night-symbolic";
                    break;
                default:
                    icon_name = "image-missing-symbolic";
                    break;
            }
            icon.icon_name = icon_name;
        });
        theme_dropdown.set_factory (factory);

        theme_dropdown.notify["selected"].connect (() => {
            var scheme = (ColorScheme) theme_dropdown.selected;
            settings.color_scheme = scheme;
            style_manager.color_scheme = scheme.to_adw_color_scheme ();
        });
        header.pack_end (theme_dropdown);

        // statusbar (создаётся после восстановления layout)

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

        // Восстанавливаем виджеты из сохранённого layout
        var dock_layout = settings.panel_layout;
        if (dock_layout != null && dock_layout != "") {
            restore_dock_widgets (dock_layout,
                                  panel_widget_left1, panel_widget_left2,
                                  panel_widget_right, panel_widget_bottom);
        } else {
            add_widget (panel_widget_left1, panel_area_left);
            add_widget (panel_widget_left2, panel_area_left);
            add_widget (panel_widget_right, panel_area_right);
            add_widget (panel_widget_bottom, panel_area_bottom);
        }

        // Создаём toggle button для BOTTOM после восстановления layout
        var bottom_toggle_btn = new Panel.ToggleButton (dock, Panel.Area.BOTTOM);
        statusbar.add_suffix (1, bottom_toggle_btn);

        Timeout.add (100, () => {
            var last_project_path = settings.current_project_path;
            if (last_project_path != null && last_project_path != "") {
                project_manager.open_project_by_path (last_project_path);
            }

            var open_docs = settings.open_documents;
            foreach (var uri in open_docs) {
                document_manager.open_document_by_uri (uri, this);
            }

            return Source.REMOVE;
        });

        // Handle file activation to open documents
        folder_view.file_activated.connect ((item) => {
            if (!item.is_directory) {
                document_manager.open_document (item.file, this);
            }
        });

        // Handle window close
        this.close_request.connect (() => {
            save_window_settings ();
            settings.open_documents = document_manager.get_open_document_uris ();
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
                        settings.open_documents = document_manager.get_open_document_uris ();
                        this.destroy ();
                    } else if (response == "discard") {
                        settings.open_documents = {};
                        this.destroy ();
                    }
                });
                dialog.present (this);
                return true;
            }
            return false;
        });
    }

    private void save_window_settings () {
        settings.panel_layout = Iide.PanelLayoutHelper.serialize_dock (dock);

        bool maximized = false;
        var surface = this.get_surface ();
        if (surface != null) {
            var toplevel = surface as Gdk.Toplevel;
            if (toplevel != null) {
                var state = toplevel.get_state ();
                maximized = (state & Gdk.ToplevelState.MAXIMIZED) != 0;
            }
        }

        if (!maximized) {
            settings.window_width = (int) this.get_width ();
            settings.window_height = (int) this.get_height ();
        }
        settings.window_maximized = maximized;
    }

    private void restore_dock_widgets (string layout_data,
                                        Panel.Widget widget_left1,
                                        Panel.Widget widget_left2,
                                        Panel.Widget widget_right,
                                        Panel.Widget widget_bottom) {
        var widgets = Iide.PanelLayoutHelper.parse_widgets (layout_data);

        Gee.HashMap<string, Panel.Widget> widget_map = new Gee.HashMap<string, Panel.Widget> ();
        widget_map.set ("Project Tree", widget_left1);
        widget_map.set ("LEFT 2", widget_left2);
        widget_map.set ("RIGHT", widget_right);
        widget_map.set ("BOTTOM", widget_bottom);

        if (widgets.size == 0) {
            var pos_left = new Panel.Position ();
            pos_left.area = Panel.Area.START;
            add_widget (widget_left1, pos_left);
            add_widget (widget_left2, pos_left);

            var pos_right = new Panel.Position ();
            pos_right.area = Panel.Area.END;
            add_widget (widget_right, pos_right);

            var pos_bottom = new Panel.Position ();
            pos_bottom.area = Panel.Area.BOTTOM;
            add_widget (widget_bottom, pos_bottom);
            return;
        }

        foreach (var info in widgets) {
            var widget = widget_map.get (info.title);
            if (widget == null) {
                continue;
            }

            var pos = new Panel.Position ();
            pos.area = (Panel.Area) info.area;
            pos.column = info.column;
            pos.row = info.row;
            pos.depth = info.depth;

            add_widget (widget, pos);
        }
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
        project_manager.open_project_dialog.begin (this);
    }
}
