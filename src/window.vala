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

    private Gtk.Button lsp_btn;
    private Gtk.Spinner lsp_spin;
    private Gtk.Label lsp_count;
    private Gtk.Popover lsp_popover;
    private Gtk.Box lsp_list_box;

    private Gtk.Button global_diag_btn;
    private Gtk.Label global_diag_label;
    private Gtk.Image global_diag_icon;
    private DiagnosticsPanel panel_widget_diagnostics;

    private BasePanel[] panel_widgets;

    public Window (Gtk.Application app) {
        Object (application: app);
        GtkSource.init ();
    }

    construct {
        settings = Iide.SettingsService.get_instance ();
        document_manager = new Iide.DocumentManager (this);
        project_manager = Iide.ProjectManager.get_instance ();
        document_manager.document_opened.connect ((widget) => {
            grid.add (widget);
            widget.raise ();
            widget.view_grab_focus ();
        });

        project_manager.project_opened.connect ((project_root) => {
            document_manager.set_workspace_root (project_root.get_uri ());
        });

        project_manager.project_closed.connect (() => {
            document_manager.set_workspace_root (null);
        });

        // Header
        var header = new Adw.HeaderBar ();
        var menu_button = new Gtk.MenuButton ();
        menu_button.icon_name = "open-menu-symbolic";

        var menu = new GLib.Menu ();
        menu.append (_("Open Project"), "app.open_project");
        menu.append (_("Quick Open"), "app.fuzzy_finder");
        menu.append (_("Search in Files"), "app.search_in_files");
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

        setup_navigation_buttons (header);

        var end_toggle_btn = new Panel.ToggleButton (dock, Panel.Area.END);
        header.pack_end (end_toggle_btn);

        set_titlebar (header);

        // Theme switcher
        var style_manager = Adw.StyleManager.get_default ();
        style_manager.color_scheme = settings.color_scheme.to_adw_color_scheme ();

        var theme_list = new Gtk.StringList ({ "System", "Light", "Dark" });
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

        // create_frames ();
        create_panels ();

        // Восстанавливаем виджеты из сохранённого layout
        restore_panels_layout ();

        // Создаём toggle button для BOTTOM после восстановления layout
        var bottom_toggle_btn = new Panel.ToggleButton (dock, Panel.Area.BOTTOM);
        statusbar.add_suffix (1, bottom_toggle_btn);

        setup_lsp_status ();
        setup_global_diag_widget ();

        project_manager.open_project_by_path (settings.current_project_path);
        restore_opened_documents ();

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
                        settings.open_documents = document_manager.get_open_document_uris ();
                        this.destroy ();
                    }
                });
                dialog.present (this);
                return true;
            }
            return false;
        });

        repair_empty_areas ();
    }

    private void restore_opened_documents () {
        var grid_data = settings.grid_layout;
        bool has_grid_docs = grid_data != null && grid_data != "";
        if (has_grid_docs) {
            restore_documents_from_grid_data (grid_data);
        } else {
            var open_docs = settings.open_documents;
            bool has_open_docs = open_docs.size > 0;
            if (has_open_docs) {
                foreach (var uri in open_docs) {
                    document_manager.open_document_by_uri (uri);
                }
            }
        }

        Timeout.add (300, () => {
            NavigationHistoryService.get_instance ().start_navigation ();
            return Source.REMOVE;
        });
    }

    private void setup_navigation_buttons (Adw.HeaderBar header) {
        // Кнопка Назад
        var back_btn = new Gtk.Button.from_icon_name ("go-previous-symbolic");
        back_btn.tooltip_text = "Назад (Alt+Left)";
        back_btn.action_name = "app.navigation_back"; // Привязываем к Action

        // Кнопка Вперед
        var forward_btn = new Gtk.Button.from_icon_name ("go-next-symbolic");
        forward_btn.tooltip_text = "Вперед (Alt+Right)";
        forward_btn.action_name = "app.navigation_forward";

        header.pack_start (back_btn);
        header.pack_start (forward_btn);
    }

    private void repair_empty_areas () {
        bool empty_start = true;
        bool empty_bottom = true;
        bool empty_end = true;
        dock.foreach_frame ((frame) => {
            var position = frame.get_position ();
            switch (position.area) {
                case Panel.Area.START:
                    empty_start = false;
                    break;
                case Panel.Area.BOTTOM:
                    empty_bottom = false;
                    break;
                case Panel.Area.END:
                    empty_end = false;
                    break;
                default:
                    break;
            }
        });

        if (empty_start) {
            var position = new Panel.Position () {
                area = Panel.Area.START
            };
            var tmp_panel = new Panel.Widget ();
            add_widget (tmp_panel, position);
            dock.remove (tmp_panel);
        }

        if (empty_bottom) {
            var position = new Panel.Position () {
                area = Panel.Area.BOTTOM
            };
            var tmp_panel = new Panel.Widget ();
            add_widget (tmp_panel, position);
            dock.remove (tmp_panel);
        }

        if (empty_end) {
            var position = new Panel.Position () {
                area = Panel.Area.END
            };
            var tmp_panel = new Panel.Widget ();
            add_widget (tmp_panel, position);
            dock.remove (tmp_panel);
        }
    }

    private void create_panels () {
        panel_widget_diagnostics = new DiagnosticsPanel ();

        panel_widgets = {
            new ProjectPanel (),
            new TerminalPanel (),
            new LogPanel (),
            panel_widget_diagnostics
        };
    }

    private void initialize_panels () {
        foreach (var panel in panel_widgets) {
            add_widget (panel, panel.initial_pos ());
        }
    }

    private void restore_panels_layout () {
        var dock_layout = settings.panel_layout;
        if (dock_layout == null || dock_layout == "") {
            initialize_panels ();
            return;
        }

        var widget_layouts = Iide.PanelLayoutHelper.parse_widgets (dock_layout);

        foreach (var panel_widget in panel_widgets) {
            var widget_layout = widget_layouts.get (panel_widget.panel_id ());
            var pos = widget_layout != null? widget_layout.to_pos () : panel_widget.initial_pos ();

            add_widget (panel_widget, pos);
        }
    }

    private void save_window_settings () {
        settings.panel_layout = Iide.PanelLayoutHelper.serialize_dock (dock);
        var grid_json = Iide.PanelLayoutHelper.serialize_grid (grid);
        settings.grid_layout = grid_json;

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

    private void restore_grid_documents (Gee.ArrayList<Iide.PanelLayoutHelper.DocumentInfo> sorted_docs) {
        uint last_col = 0;
        foreach (var doc_info in sorted_docs) {
            if (doc_info.column > last_col) {
                last_col = doc_info.column;
            }
        }

        for (uint i = 1; i <= last_col; i++) {
            grid.insert_column (i);
        }

        foreach (var doc_info in sorted_docs) {
            var file = GLib.File.new_for_uri (doc_info.uri);
            var pos = new Panel.Position ();
            pos.area = Panel.Area.CENTER;
            pos.column = doc_info.column;
            pos.row = doc_info.row;
            document_manager.open_document (file, pos);
        }
    }

    private void restore_documents_from_grid_data (string grid_data) {
        var docs = Iide.PanelLayoutHelper.parse_grid_documents (grid_data);
        if (docs.size == 0) {
            return;
        }

        var sorted_docs = new Gee.ArrayList<Iide.PanelLayoutHelper.DocumentInfo> ();
        foreach (var doc in docs) {
            sorted_docs.add (doc);
        }
        sorted_docs.sort ((a, b) => {
            int col_cmp = (int) (a.column - b.column);
            if (col_cmp != 0)return col_cmp;
            return (int) (a.row - b.row);
        });

        restore_grid_documents (sorted_docs);
    }

    public void save_modified () {
        foreach (var entry in document_manager.documents.entries) {
            var widget = entry.value;
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

    public Iide.DocumentManager get_document_manager () {
        return document_manager;
    }

    public SourceView ? get_active_source_view () {
        // 1. Получаем последний сфокусированный виджет в сетке панелей
        Panel.Widget? active_widget = this.get_grid ().get_most_recent_frame ().get_visible_child ();

        if (active_widget == null)return null;

        return (active_widget as TextView) ? .source_view;
    }

    private void setup_lsp_status () {
        // 1. Создаем кнопку для Statusbar
        var btn_content = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
        lsp_spin = new Gtk.Spinner ();
        lsp_count = new Gtk.Label ("0");
        btn_content.append (lsp_spin);
        btn_content.append (lsp_count);

        lsp_btn = new Gtk.Button () { child = btn_content, visible = false };
        lsp_btn.add_css_class ("flat");
        this.statusbar.add_prefix (100, lsp_btn);

        // 2. Создаем Popover
        lsp_popover = new Gtk.Popover ();
        lsp_popover.set_parent (lsp_btn);
        var scroll = new Gtk.ScrolledWindow () {
            max_content_height = 300,
            propagate_natural_height = true,
            width_request = 350 // Добавляем фиксированную минимальную ширину
        };
        lsp_list_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
        lsp_list_box.add_css_class ("boxed-list"); // Стиль Adwaita для связанных строк

        scroll.set_child (lsp_list_box);
        lsp_popover.set_child (scroll);

        lsp_btn.clicked.connect (() => lsp_popover.popup ());

        // 3. Подписка на сервис
        IdeLspService.get_instance ().tasks_changed.connect (update_lsp_ui);
    }

    private void update_lsp_ui (Gee.List<LspTaskInfo?> tasks) {
        // Очистка списка
        Gtk.Widget? child;
        while ((child = lsp_list_box.get_first_child ()) != null)
            lsp_list_box.remove (child);

        if (tasks.size == 0) {
            lsp_btn.hide ();
            lsp_popover.popdown ();
            return;
        }

        lsp_btn.show ();
        lsp_spin.start ();
        lsp_count.label = tasks.size.to_string ();

        foreach (var task in tasks) {
            var row = new Adw.ActionRow () {
                title = task.server_name,
                subtitle = task.message
            };

            if (task.percentage >= 0) {
                var progress = new Gtk.ProgressBar () {
                    fraction = task.percentage / 100.0,
                    valign = Gtk.Align.CENTER
                };
                progress.add_css_class ("osd"); // Делает полоску тоньше и аккуратнее
                row.add_suffix (progress);
            }

            lsp_list_box.append (row);
        }
    }

    private void setup_global_diag_widget () {
        var content = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
        global_diag_icon = new Gtk.Image.from_icon_name ("emblem-ok-symbolic");
        global_diag_label = new Gtk.Label ("OK");

        content.append (global_diag_icon);
        content.append (global_diag_label);

        global_diag_btn = new Gtk.Button ();
        global_diag_btn.set_child (content);
        global_diag_btn.add_css_class ("flat");

        // Привязываем действие переключения панели
        global_diag_btn.clicked.connect (() => {
            panel_widget_diagnostics.raise ();
        });

        this.statusbar.add_prefix (50, global_diag_btn);

        // Подключаемся к сервису для обновления состояния
        DiagnosticsService.get_instance ().total_count_changed.connect (update_global_diag_status);
    }

    private void update_global_diag_status (int errors, int warns) {
        if (errors == 0 && warns == 0) {
            global_diag_icon.icon_name = "emblem-ok-symbolic";
            global_diag_label.label = "OK";
            global_diag_btn.remove_css_class ("error-state"); // Можно добавить для цвета
        } else {
            global_diag_icon.icon_name = "dialog-error-symbolic";
            global_diag_label.label = @"$errors / $warns";
            global_diag_btn.add_css_class ("error-state");
        }
    }
}