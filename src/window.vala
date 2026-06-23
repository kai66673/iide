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
    private Iide.TextLineMarkService bookmark_service;
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
    private string app_error_icon_name;

    private BasePanel[] panel_widgets;

    public Window (Gtk.Application app) {
        Object (application: app);
        GtkSource.init ();
    }

    construct {
        settings = SettingsService.get_instance ();
        document_manager = new DocumentManager (this);
        project_manager = new ProjectManager (this);
        bookmark_service = new TextLineMarkService ("bookmark");
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
        menu.append (_("Open Project"), "app.open-project");
        menu.append (_("Quick Open"), "app.fuzzy-finder");
        menu.append (_("Search Symbol"), "app.search-symbol");
        menu.append (_("Search in Files"), "app.search-in-files");
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

            // ПРИНУДИТЕЛЬНО добавляем класс на окно, чтобы CSS его увидел
            if (scheme == ColorScheme.DARK) {
                this.add_css_class ("dark");
            } else {
                this.remove_css_class ("dark");
            }
        });
        if (settings.color_scheme == ColorScheme.DARK) {
            this.add_css_class ("dark");
        }

        header.pack_end (theme_dropdown);

        // statusbar (создаётся после восстановления layout)

        create_panels ();

        // Восстанавливаем виджеты из сохранённого layout
        restore_panels_layout ();

        // Создаём toggle button для BOTTOM после восстановления layout
        var bottom_toggle_btn = new Panel.ToggleButton (dock, Panel.Area.BOTTOM);
        statusbar.add_suffix (1, bottom_toggle_btn);

        setup_lsp_status ();
        setup_global_diag_widget ();

        repair_empty_areas ();
        setup_switch_document_controller ();
        
        project_manager.open_project_by_path (settings.current_project_path);

        // Handle window close
        this.close_request.connect (() => {
            save_window_settings ();
            this.handle_window_close_async.begin ();
            
            return true;
        });
    }

    private async void handle_window_close_async () {
        bool save_confirmed = yield this.document_manager.confirm_save_modified_documents_async (this);
        if (!save_confirmed)
            return;
    
        bookmark_service.write_cache_to_json_file ();
        yield project_manager.shutdown_all_running_lsp_servers_async ();

        this.destroy ();
    }

    private void setup_switch_document_controller() {
        var key_controller = new Gtk.EventControllerKey ();
        key_controller.set_propagation_phase (Gtk.PropagationPhase.CAPTURE);

        // 1. ПЕРЕХВАТ НАЖАТИЯ (Открытие окна и циклическое листание)
        key_controller.key_pressed.connect ((keyval, keycode, state) => {
            var modifiers = state & (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.SHIFT_MASK);
            bool is_ctrl = (modifiers & Gdk.ModifierType.CONTROL_MASK) != 0;
            bool is_shift = (modifiers & Gdk.ModifierType.SHIFT_MASK) != 0;

            if ((keyval == Gdk.Key.Tab || keyval == Gdk.Key.ISO_Left_Tab) && is_ctrl) {
                var tab_switcher_popup = new TabSwitcherPopup (this, is_shift);
                tab_switcher_popup.present ();
                return true; // Полностью глушим фокус док-панелей libpanel
            }

            return false;
        });

        ((Gtk.Widget) this).add_controller (key_controller);
    }

    private void setup_navigation_buttons (Adw.HeaderBar header) {
        // Кнопка Назад
        var back_btn = new Gtk.Button.from_icon_name ("go-previous-symbolic");
        back_btn.tooltip_text = "Назад (Alt+Left)";
        back_btn.action_name = "app.navigation-back"; // Привязываем к Action

        // Кнопка Вперед
        var forward_btn = new Gtk.Button.from_icon_name ("go-next-symbolic");
        forward_btn.tooltip_text = "Вперед (Alt+Right)";
        forward_btn.action_name = "app.navigation-forward";

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
            new BookmarksPanel (),
            panel_widget_diagnostics,
            new LspMonitorPanel(),
        };
    }

    public void initialize_panels () {
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
        this.project_manager.save_documents_grid ();

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

        if (active_widget == null)
            return null;

        return (active_widget as TextView) ? .source_view;
    }
    
    public TextView ? get_active_text_view () {
        // 1. Получаем последний сфокусированный виджет в сетке панелей
        Panel.Widget? active_widget = this.get_grid ().get_most_recent_frame ().get_visible_child ();

        if (active_widget == null)
            return null;

        return (active_widget as TextView);
    }

    public void start_switch_document(bool next) {
        // TODO: implement...
        if (next) {
            LoggerService.get_instance ().info ("SD", "TODO next...");
        } else {
            LoggerService.get_instance ().info ("SD", "TODO prev...");
        }
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
        var lsp_service = LspService.get_instance ();
        lsp_service.tasks_changed.connect (update_lsp_ui);
        DiagnosticsService.get_instance ().lsp_stopped.connect (() => {
            lsp_service.clear_lsp_tasks ();
        });
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
        app_error_icon_name = SymbIconProvider.get_instance ().icon_name (IconID.APP_ERROR);
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
        var diagnostics_service = DiagnosticsService.get_instance ();
        diagnostics_service.total_count_changed.connect (update_global_diag_status);
        diagnostics_service.lsp_stopped.connect (clear_global_diag_status);
    }

    private void clear_global_diag_status () {
        update_global_diag_status (0, 0);
    }

    private void update_global_diag_status (int errors, int warns) {
        if (errors == 0 && warns == 0) {
            global_diag_icon.icon_name = "emblem-ok-symbolic";
            global_diag_label.label = "OK";
            global_diag_btn.remove_css_class ("error-state"); // Можно добавить для цвета
        } else {
            global_diag_icon.icon_name = app_error_icon_name;
            global_diag_label.label = @"$errors / $warns";
            global_diag_btn.add_css_class ("error-state");
        }
    }

    public void clear_documents_grid () {
        Gtk.Widget? paned_widget = this.grid.get_first_child ();
        Panel.Paned? paned = paned_widget as Panel.Paned;
        if (paned != null) {
            Gtk.Widget? paned_child = paned.get_first_child ();
            while (paned_child != null) {
                Gtk.Widget? next = paned_child.get_next_sibling ();
                paned_child.unparent ();
                paned_child.destroy ();
                paned_child = next;
            }
        }
    }

    public void restore_documents_grid (Gee.ArrayList<PanelLayoutHelper.DocumentInfo> docs) {
        if (docs.size == 0)
            return;

        docs.sort ((a, b) => {
            int col_cmp = (int) (a.column - b.column);
            if (col_cmp != 0)return col_cmp;
            return (int) (a.row - b.row);
        });

        foreach (var doc_info in docs) {
            var file = GLib.File.new_for_uri (doc_info.uri);
            var pos = new Panel.Position ();
            pos.area = Panel.Area.CENTER;
            pos.column = doc_info.column;
            pos.row = doc_info.row;
            document_manager.open_document (file, pos);
        }
    }
}