using GLib;
using Gtk;
using Adw;
using Gee;

namespace Iide {

    public class LspMonitorPanel : BasePanel {
        private Adw.PreferencesGroup main_group;
        private Gtk.ListBox list_box;
        
        // СТАЛО: ОДНО ЕДИНСТВЕННОЕ текстовое поле на всю панель!
        private Gtk.TextView single_log_view;
        private Gtk.Label log_console_title;

        // Переключатели режимов вместо тяжелого ViewStack
        private Gtk.ToggleButton proto_log_button;
        private Gtk.ToggleButton stderr_log_button;

        private HashMap<string, LspServerRow> row_cache = new HashMap<string, LspServerRow> ();
        private string? currently_selected_server = null;

        public LspMonitorPanel () {
            base ("LSP Monitor", "utilities-system-monitor-symbolic");

            // 1. Верхняя часть: Список серверов (Выключаем vexpand!)
            this.list_box = new Gtk.ListBox ();
            this.list_box.set_selection_mode (Gtk.SelectionMode.NONE);
            this.list_box.add_css_class ("boxed-list");
            this.list_box.row_activated.connect (this.on_server_row_selected);

            this.main_group = new Adw.PreferencesGroup () {
                title = "Active Language Servers",
                description = "No active LSP servers running for this workspace.",
                vexpand = false, // ЧИСТО: Список серверов занимает место строго по высоте своих строк!
                hexpand = true
            };
            this.main_group.add (this.list_box);

            // 2. Нижняя часть: Одиночное текстовое поле логов
            this.single_log_view = new Gtk.TextView () { 
                editable = false, 
                cursor_visible = false, 
                wrap_mode = Gtk.WrapMode.WORD_CHAR 
            };
            this.single_log_view.add_css_class ("monospace");

            // ИСПРАВЛЕНИЕ СКРОЛЛА: Снижаем минимальный барьер высоты логов до 100px!
            // Теперь панель сможет аккуратно сжиматься по вертикали, уступая место коду.
            var log_scroll = new Gtk.ScrolledWindow () { 
                child = this.single_log_view,
                vexpand = true,  // Забирает ВСЕ свободное пространство боковой области!
                hexpand = true,
                min_content_height = 100, // Минимальная комфортная высота консоли логов
                min_content_width = 150
            };

            // Автоскролл (без изменений)
            this.single_log_view.get_buffer ().changed.connect_after (() => {
                Gtk.TextIter end;
                this.single_log_view.get_buffer ().get_end_iter (out end);
                var mark = this.single_log_view.get_buffer ().create_mark (null, end, false);
                this.single_log_view.scroll_to_mark (mark, 0.0, true, 0.0, 1.0);
            });

            // Кнопки-переключатели (без изменений)
            var switcher_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            switcher_box.add_css_class ("linked");
            switcher_box.halign = Gtk.Align.CENTER;

            this.proto_log_button = new Gtk.ToggleButton.with_label ("Log Message") { active = true };
            this.stderr_log_button = new Gtk.ToggleButton.with_label ("System (Stderr)");
            this.stderr_log_button.set_group (this.proto_log_button);

            switcher_box.append (this.proto_log_button);
            switcher_box.append (this.stderr_log_button);

            this.proto_log_button.toggled.connect (this.on_sync_view_buffer);
            this.stderr_log_button.toggled.connect (this.on_sync_view_buffer);

            this.log_console_title = new Gtk.Label ("Console Output: None") {
                xalign = 0, margin_top = 12, margin_bottom = 6
            };
            this.log_console_title.add_css_class ("heading");

            // Собираем консольную коробку (Удален некорректный min_content_height)
            var console_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 4);
            console_box.vexpand = true;
            console_box.hexpand = true;
            console_box.append (this.log_console_title);
            console_box.append (switcher_box);
            console_box.append (log_scroll); 

            // Итоговый вертикальный холст панели
            var layout_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 8) {
                margin_start = 12, margin_end = 12, margin_top = 12, margin_bottom = 12,
                vexpand = true,
                hexpand = true
            };
            layout_box.append (this.main_group);
            layout_box.append (console_box);

            // ===================================================================
            // ОПТИМИЗАЦИЯ ВEРСТКИ: ЗАВЕРТЫВАЕМ ВЕСЬ ЛЕЙАУТ В ОБЩИЙ СКРОЛЛ
            // ===================================================================
            var main_scrolled_window = new Gtk.ScrolledWindow () {
                vexpand = true,  // Общий скролл занимает ВСЮ высоту боковой панели Libpanel
                hexpand = true,
                hscrollbar_policy = Gtk.PolicyType.NEVER, // Запрещаем горизонтальный скролл панели
                vscrollbar_policy = Gtk.PolicyType.AUTOMATIC,
                child = layout_box // Кладем весь наш бокс внутрь
            };

            this.set_child (main_scrolled_window);

            // Системные биндинги проекта
            // ===================================================================
            // СВЯЗЫВАНИЕ СИГНАЛА РЕГИСТРАЦИИ КЛИЕНТА (РЕАКТИВНЫЙ UI)
            // ===================================================================
            var lsp_service = LspService.get_instance ();
            
            lsp_service.client_registered.connect ((client) => {
                // Переводим исполнение строго в очередь главного UI-потока
                Idle.add (() => {
                    string name = client.name ();
                    
                    // Если строка для этого сервера уже добавлена — игнорируем
                    if (this.row_cache.has_key (name)) return Source.REMOVE;

                    this.main_group.description = "Select a server to view its isolated streams";

                    // Создаем строку и точечно добавляем её в список!
                    var row = new LspServerRow (client);
                    this.list_box.append (row);
                    this.row_cache.set (name, row);
                    
                    return Source.REMOVE;
                });
            });

            var prj_manager = ProjectManager.get_instance ();
            prj_manager.project_closed.connect (this.on_project_closed);

            // Секундный таймер обновления точек-статусов
            Timeout.add (1000, () => { this.tick_updates (); return Source.CONTINUE; });
        }

        public override Panel.Position initial_pos () {
            return new Panel.Position () { area = Panel.Area.BOTTOM };
        }

        public override string panel_id () {
            return "LspMonitorPanel";
        }

        private void on_server_row_selected (Gtk.ListBoxRow base_row) {
            var server_row = base_row as LspServerRow;
            if (server_row == null) return;

            this.currently_selected_server = server_row.client.name ();
            this.log_console_title.label = @"Console Output: $(this.currently_selected_server)";

            // Перенаправляем на метод синхронизации буфера
            this.on_sync_view_buffer ();
        }

        /**
         * УНИВЕРСАЛЬНЫЙ СИНХРОНИЗАТОР ЭКРАНА:
         * Меняет буфер в единственном TextView в зависимости от того, какая кнопка нажата
         */
        private void on_sync_view_buffer () {
            if (this.currently_selected_server == null || !this.row_cache.has_key (this.currently_selected_server)) {
                return;
            }

            var row = this.row_cache.get (this.currently_selected_server);

            // Атомарно переключаем буфер. Одиночный TextView на экране проглотит это без ассертов!
            if (this.proto_log_button.active) {
                this.single_log_view.set_buffer (row.protocol_log_buffer);
            } else if (this.stderr_log_button.active) {
                this.single_log_view.set_buffer (row.stderr_log_buffer);
            }

            // Мягко прокручиваем экран вниз
            Gtk.TextIter end;
            this.single_log_view.get_buffer ().get_end_iter (out end);
            this.single_log_view.scroll_to_iter (end, 0.0, false, 0.0, 0.0);
        }

        public void tick_updates () {
            foreach (var row in this.row_cache.values) {
                row.refresh_ui ();
            }
        }

        private void on_project_closed () {
            this.list_box.remove_all ();
            this.row_cache.clear ();
            this.single_log_view.set_buffer (null);
            this.currently_selected_server = null;
            this.log_console_title.label = "Console Output: None";
            this.main_group.description = "No active LSP servers running.";
        }
    }
}
