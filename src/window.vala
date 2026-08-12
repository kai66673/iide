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
    public WindowSession session;

    private SettingsService settings;

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

    public GLib.File project_root { get; construct set; }

    private Gtk.PopoverMenu context_popover;
    private SimpleActionGroup menu_action_group;

    public Window (Gtk.Application app, GLib.File project_root) {
        Object (application: app, project_root: project_root);
        GtkSource.init ();
    }

    construct {
        settings = SettingsService.get_instance ();

        session = new WindowSession (this, project_root);

        session.dap_service.active_line_changed.connect (session.document_manager.highlight_debugger_active_line);
        session.dap_service.session_state_changed.connect ((state, old_state) => {
            if (state == DapSessionState.EMPTY) {
                session.document_manager.clear_all_debugger_highlights ();
            }
        });
        
        session.document_manager.document_opened.connect ((widget) => {
            grid.add (widget);
            widget.raise ();
            widget.view_grab_focus ();
        });

        session.project_manager.project_opened.connect ((project_root) => {
            session.document_manager.set_workspace_root (project_root.get_uri ());
        });

        session.project_manager.project_closed.connect (() => {
            session.document_manager.set_workspace_root (null);
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

        var dap_toolbar = new DapToolbar (this.session);
        header.pack_end (dap_toolbar);

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
        
        session.project_manager.open_project_by_path (settings.current_project_path);

        // Handle window close
        this.close_request.connect (() => {
            save_window_settings ();
            this.handle_close ();
            return true;
        });

        setup_dock_headers_events ();
    }

    private void setup_dock_headers_events () {
        var click_gesture = new Gtk.GestureClick ();
        click_gesture.set_button (3); // Правый клик

        click_gesture.pressed.connect ((n_press, x, y) => {
            // 1. Находим самый глубокий виджет в точке клика (работает на всем пространстве Дока)
            var target_widget = dock.pick (x, y, Gtk.PickFlags.DEFAULT);
            
            if (target_widget != null) {
                Gtk.Widget? current = target_widget;
                
                // 2. Поднимаемся вверх, ища контейнер фрейма (Panel.Frame)
                while (current != null && current != dock) {
                    
                    // Проверяем, уперлись ли мы во фрейм libpanel
                    if (current.get_type ().name () == "PanelFrame" || current is Panel.Frame) {
                        var frame = current as Panel.Frame;

                        var panels = new Gee.ArrayList<Iide.BasePanel> ();
                        for (var i = 0; i < frame.get_n_pages (); i++) {
                            var panel = frame.get_page (i) as Iide.BasePanel;
                            if (panel != null) {
                                panels.add (panel);
                            }
                        }

                        this.show_context_menu_for_panels(frame, panels, x, y);

                        break;
                    }
                    current = current.get_parent ();
                }
            }
        });

        dock.add_controller (click_gesture);
    }

    private void show_context_menu_for_panels (Panel.Frame frame, Gee.ArrayList<Iide.BasePanel> panels, double x, double y) {
        // 1. Очищаем старое меню и группу экшенов, если они были
        if (context_popover != null) {
            context_popover.unparent ();
        }
        
        var menu_model = new GLib.Menu ();
        menu_action_group = new SimpleActionGroup ();
    
        var context_panels = new Gee.ArrayList<Iide.BasePanel> ();
        context_panels.add_all (panels);
        foreach (var panel in this.panel_widgets) {
            if (!panel.is_content_visible) {
                context_panels.add (panel);
            }
        }

        // 2. Наполняем меню пунктами-переключателями (Check items)
        foreach (var panel in context_panels) {
            string action_name = "toggle_" + panel.panel_id ();
            
            // Создаем State-full Action (экшен с состоянием типа boolean)
            // Начальное состояние берем из текущей видимости контента панели
            var action = new SimpleAction.stateful (
                action_name, 
                null, 
                new GLib.Variant.boolean (panel.is_content_visible)
            );

            // При клике на пункт меню инвертируем состояние экшена и самой панели
            action.activate.connect ((param) => {
                bool current_state = action.get_state ().get_boolean ();
                bool new_state = !current_state;
                
                action.set_state (new GLib.Variant.boolean (new_state));
                if (new_state) {
                    // Включаем видимость
                    frame.add (panel);
                    panel.add_to_frame (frame);
                    panel.raise ();
                } else {
                    // Выключаем видимость
                    panel.remove_from_frame (frame);
                    this.handle_panel_removed_from_frame (frame);
                }
            });

            menu_action_group.add_action (action);

            // Создаем пункт меню, который отображается как Checkbox
            var menu_item = new GLib.MenuItem (panel.title, "dock_menu." + action_name);
            menu_model.append_item (menu_item);
        }

        // 3. Создаем виджет PopoverMenu в GTK4
        context_popover = new Gtk.PopoverMenu.from_model (menu_model);
        context_popover.set_parent (this.dock); // Привязываем к доку
        context_popover.set_has_arrow (true);

        // Регистрируем нашу группу экшенов под префиксом "dock_menu"
        context_popover.insert_action_group ("dock_menu", menu_action_group);

        // 4. Позиционируем меню ровно в место клика мыши
        Gdk.Rectangle rect = Gdk.Rectangle ();
        rect.x = (int)x;
        rect.y = (int)y;
        rect.width = 1;
        rect.height = 1;
        
        context_popover.set_pointing_to (rect);
        context_popover.popup ();
    }

    private void handle_panel_removed_from_frame (Panel.Frame frame) {
        var pages_count = frame.get_n_pages ();
        if (pages_count > 0) {
            return;
        }
        var frame_area_empty = true;
        var frame_area = frame.get_position ().area;
        this.dock.foreach_frame ((dock_frame) => {
            if (dock_frame != frame && dock_frame.visible && dock_frame.get_position ().area == frame_area) {
                frame_area_empty = false;
            }
        });
        if (frame_area_empty) {
            frame.activate_action ("frame.close", null);
        } else {
            frame.set_visible (false);
        }
    }

    private void handle_close () {
        // Если есть изменённые документы — показываем диалог
        if (this.session.document_manager.has_modified_documents ()) {
            var dialog = new Adw.AlertDialog (
                _("Unsaved Changes"),
                _("You have unsaved documents. Save before closing?")
            );

            dialog.add_response ("cancel", _("Cancel"));
            dialog.add_response ("discard", _("Discard"));
            dialog.add_response ("save", _("Save"));
            dialog.set_response_appearance ("save", Adw.ResponseAppearance.SUGGESTED);
            dialog.set_close_response ("cancel");

            dialog.response.connect ((response) => {
                switch (response) {
                    case "save":
                        this.session.document_manager.save_modified_documents ();
                        do_close ();
                        break;
                    case "discard":
                        do_close ();
                        break;
                    case "cancel":
                    default:
                        break;
                }
            });

            dialog.present (this);
        } else {
            do_close ();
        }
    }

    private void do_close () {
        foreach (var mark_service in this.session.marks_service) {
            mark_service.write_cache_to_json_file ();
        }

        // Закрываем LSP-серверы, но не ждём — окно уже закрывается
        session.project_manager.shutdown_all_running_lsp_servers_async.begin ();

        // Даём GC время завершить операции, затем уничтожаем окно
        Timeout.add (200, () => {
            this.destroy ();
            return Source.REMOVE;
        });
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
            if (frame.visible) {
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
        panel_widget_diagnostics = new DiagnosticsPanel (this.session);

        panel_widgets = {
            new ProjectPanel (this.session),
            new TerminalPanel (this.session),
            new LogPanel (this.session),
            new BookmarksPanel (this.session),
            panel_widget_diagnostics,
            new LspMonitorPanel (this.session),
            new DapConsolePanel (this.session),
            new DapVariablesPanel (this.session),
            new DapCallStackPanel (this.session),
        };
    }

    public void initialize_panels () {
        foreach (var panel in panel_widgets) {
            panel.initial_add (this);
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
            if (widget_layout != null) {
                panel_widget.initial_add (this, widget_layout.to_pos ());
            }
        }
    }

    private void save_window_settings () {
        this.session.project_manager.save_documents_grid ();

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
        foreach (var entry in session.document_manager.documents.entries) {
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
        var dialog = new Gtk.FileDialog () {
            title = _("Open Project"),
            modal = true
        };

        var last_dir = settings.last_open_directory;
        if (last_dir != null && last_dir != "") {
            dialog.initial_folder = GLib.File.new_for_path (last_dir);
        }

        dialog.select_folder.begin (this, null, (obj, res) => {
            try {
                var file = dialog.select_folder.end (res);
                if (file == null) return;

                settings.current_project_path = file.get_path ();
                settings.add_recent_project (file.get_path ());
                if (file.get_parent () != null) {
                    settings.last_open_directory = file.get_parent ().get_path ();
                }

                var app = this.application as Iide.Application;
                var new_win = new Iide.Window (app, file);
                new_win.present ();

                this.destroy ();
            } catch (Error e) {
                // User dismissed dialog
            }
        });
    }

    public Iide.DocumentManager get_document_manager () {
        return session.document_manager;
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
        this.session.lsp_service.tasks_changed.connect (update_lsp_ui);
        this.session.diagnostics_service.lsp_stopped.connect (() => {
            session.lsp_service.clear_lsp_tasks ();
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
        this.session.diagnostics_service.total_count_changed.connect (update_global_diag_status);
        this.session.diagnostics_service.lsp_stopped.connect (clear_global_diag_status);
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
            session.document_manager.open_document (file, pos);
        }
    }
}