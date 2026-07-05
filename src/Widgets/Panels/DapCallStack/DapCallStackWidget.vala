/*
*/
namespace Iide {

    public class DapCallStackWidget : Gtk.Box {
        private Gtk.TreeView tree_view;
        private Gtk.TreeStore tree_store;
        private Gtk.ScrolledWindow scroll_window;

        public DapCallStackWidget () {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);

            // Схема TreeStore:
            // Колонка 0: Отображаемый текст строки (string)
            // Колонка 1: Си-указатель на объект данных (GLib.Object -> DapThread или DapStackFrame)
            // Колонка 2: Флаг заглушки (bool)
            this.tree_store = new Gtk.TreeStore (3, typeof (string), typeof (GLib.Object), typeof (bool));

            this.tree_view = new Gtk.TreeView.with_model (this.tree_store);
            this.tree_view.enable_tree_lines = true;
            this.tree_view.headers_visible = false; // Скрываем заголовки, для стека они не нужны

            // Добавляем единственную текстовую колонку рендеринга
            var renderer = new Gtk.CellRendererText ();
            renderer.font = "Monospace 10";
            var column = new Gtk.TreeViewColumn ();
            column.pack_start (renderer, true);
            column.add_attribute (renderer, "text", 0);
            this.tree_view.append_column (column);

            this.scroll_window = new Gtk.ScrolledWindow ();
            this.scroll_window.set_child (this.tree_view);
            this.scroll_window.vexpand = true;
            this.append (this.scroll_window);

            // МOСТЫ ВВОДА:
            // 1. Ленивое раскрытие потоков по стрелочке ▶
            this.tree_view.row_expanded.connect (this.on_thread_row_expanded_lazy);

            // 2. Клик по строке функции (выбор кадра стека)
            this.tree_view.row_activated.connect (this.on_stack_row_clicked);
            //  this.tree_view.cursor_changed.connect (this.on_ui_cursor_changed);

            // СИГНАЛЫ БЭКЕНДА
            DapService.get_instance ().threads_updated.connect (this.on_threads_synchronized);
            DapService.get_instance ().session_state_changed.connect (this.on_session_state_changed);
        }

        /**
         * ОБНОВЛЕНИЕ СПИСКА ПОТОКОВ ПРИ ОСТАНОВЕ
         */
        private void on_threads_synchronized (Gee.ArrayList<DapThread> threads) {
            Idle.add_full (Priority.DEFAULT_IDLE, () => {
                this.tree_store.clear ();

                foreach (var t in threads) {
                    Gtk.TreeIter root_iter;
                    this.tree_store.append (out root_iter, null);

                    string label_text = @"Thread $(t.id): $(t.name)";
                    this.tree_store.set (root_iter, 0, label_text, 1, t, 2, false, -1);

                    // Кладем заглушку, чтобы гарантированно зажечь стрелочку ▶ ! [INDEX]
                    Gtk.TreeIter dummy_iter;
                    this.tree_store.append (out dummy_iter, root_iter);
                    this.tree_store.set (dummy_iter, 0, "Loading...", 1, null, 2, true, -1);
                    
                    // Эвристика: Автоматически раскрываем первый (главный) поток для удобства пользователя!
                    if (t.id == 1) {
                        Gtk.TreePath p = this.tree_store.get_path (root_iter);
                        this.tree_view.expand_row (p, false);
                    }
                }
                return Source.REMOVE;
            });
        }

        /**
         * ЛЕНИВАЯ ВЫКАЧКА СТЕКА ПО КЛИКУ НА ▶ ПОТОКА
         */
        private void on_thread_row_expanded_lazy (Gtk.TreeIter parent_iter, Gtk.TreePath path) {
            GLib.Object raw_obj;
            this.tree_store.get (parent_iter, 1, out raw_obj, -1);
            
            var thread = raw_obj as DapThread;
            if (thread == null || thread.stack_fetched) return;

            this.load_frames_to_ui_async.begin (thread, parent_iter);
        }

        private async void load_frames_to_ui_async (DapThread thread, Gtk.TreeIter parent_iter) {
            bool success = yield DapService.get_instance ().fetch_stack_frames_lazy_async (thread);

            if (success) {
                Idle.add_full (Priority.DEFAULT_IDLE, () => {
                    this.tree_view.row_expanded.disconnect (this.on_thread_row_expanded_lazy);

                    // Удаляем "Loading..." заглушку [INDEX]
                    Gtk.TreeIter child_iter;
                    if (this.tree_store.iter_children (out child_iter, parent_iter)) {
                        bool is_dummy;
                        this.tree_store.get (child_iter, 2, out is_dummy, -1);
                        if (is_dummy) this.tree_store.remove (ref child_iter);
                    }

                    // Накатываем честные кадры функций Python [INDEX]
                    foreach (var frame in thread.frames) {
                        Gtk.TreeIter f_iter;
                        this.tree_store.append (out f_iter, parent_iter);

                        string clean_file = Path.get_basename (frame.file_uri.replace("file://", ""));
                        string display_text = @" %s()  [%s:%d]".printf (frame.function_name, clean_file, frame.line + 1);

                        this.tree_store.set (f_iter, 0, display_text, 1, frame, 2, false, -1);
                    }

                    // Железно фиксируем раскрытие
                    Gtk.TreePath p = this.tree_store.get_path (parent_iter);
                    this.tree_view.expand_row (p, false);

                    this.tree_view.row_expanded.connect (this.on_thread_row_expanded_lazy);
                    return Source.REMOVE;
                });
            }
        }

        /**
         * КЛИК ПО СТРОКЕ ФУНКЦИИ (Двойной клик или Enter) — Смена кадра!
         */
        private void on_stack_row_clicked (Gtk.TreePath path, Gtk.TreeViewColumn? column) {
            Gtk.TreeIter iter;
            if (this.tree_store.get_iter (out iter, path)) {
                GLib.Object raw_obj;
                this.tree_store.get (iter, 1, out raw_obj, -1);

                var frame = raw_obj as DapStackFrame;
                if (frame != null && frame.file_uri != "") {
                    
                    // ===================================================================
                    // ЖEЛEЗНОE ИСПРАВЛEНИE ПEРEХOДА:
                    // Мы строго уводим смену активного кадра стека в очередь Idle!
                    // Это гарантирует, что GTK4 сначала полностью завершит Си-цикл 
                    // обработки клика мыши, закроет свои внутренние транзакции, 
                    // и лишь затем чистый бэкенд-сервис DapService начнет дергать 
                    // сетевые сокеты для выкачки новых переменных!
                    // ===================================================================
                    Idle.add_full (Priority.DEFAULT, () => {
                        DapService.get_instance ().switch_active_frame (frame);
                        return Source.REMOVE; // Выполнить строго один раз!
                    });
                }
            }
        }

        /**
         * ОБРАБОТЧИК ОДИНOЧНОГO КЛИКА И НАВИГАЦИИ С КЛАВИАТУРЫ
         */
        private void on_ui_cursor_changed () {
            var selection = this.tree_view.get_selection ();
            Gtk.TreeModel model;
            Gtk.TreeIter iter;

            // Вытаскиваем итератор текущей выделенной пользователем строки
            if (selection.get_selected (out model, out iter)) {
                GLib.Object raw_obj;
                this.tree_store.get (iter, 1, out raw_obj, -1);

                var frame = raw_obj as DapStackFrame;
                
                // Переключаем контекст, только если выделили честный кадр стека (функцию)
                if (frame != null && frame.file_uri != "") {
                    
                    // Железобетонная развязка Си-стека через Idle.add
                    Idle.add_full (Priority.DEFAULT, () => {
                        DapService.get_instance ().switch_active_frame (frame);
                        return Source.REMOVE;
                    });
                }
            }
        }

        private void on_session_state_changed (DapSessionState state, DapSessionState old_state) {
            if (state == DapSessionState.EMPTY) {
                Idle.add_full (Priority.DEFAULT_IDLE, () => {
                    this.tree_store.clear ();
                    return Source.REMOVE;
                });
            }
        }
    }
}
