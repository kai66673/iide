/**
 * ПОЛНОЦЕННЫЙ ДРЕВОВИДНЫЙ ВИДЖЕТ ИНСПЕКЦИИ ПАМЯТИ (Variables View)
 * Реализован на базе стабильного Gtk.TreeStore для 100% контроля ленивой загрузки! [INDEX, INDEX]
 */
public class Iide.DapVariablesWidget : Gtk.Box {
    private weak WindowSession session;

    private Gtk.TreeView tree_view;
    private Gtk.TreeStore tree_store;
    private Gtk.ScrolledWindow scroll_window;
    private LoggerService logger;

    public DapVariablesWidget (WindowSession session) {
        Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);
        this.session = session;
        this.logger = session.logger_service;

        // 1. Инициализируем TreeStore. Задаем три Си-колонки в модели данных:
        //    Колонка 0: Имя (string)
        //    Колонка 1: Тип (string)
        //    Колонка 2: Значение (string)
        //    Колонка 3: Скрытый Си-указатель на сам объект DapVariable (GLib.Object) [INDEX]
        //    Колонка 4: Флаг-маркер заглушки (bool)
        this.tree_store = new Gtk.TreeStore (5, 
            typeof (string), 
            typeof (string), 
            typeof (string), 
            typeof (GLib.Object),
            typeof (bool)
        );

        // 2. Создаем TreeView и скармливаем ему модель [INDEX]
        this.tree_view = new Gtk.TreeView.with_model (this.tree_store);
        this.tree_view.add_css_class ("data-table");
        this.tree_view.enable_tree_lines = true; // Нарисует красивые тонкие линии вложенности

        // 3. ФОРМИРУЕМ ВИЗУАЛЬНЫЕ КОЛОНКИ НА ЭКРАНЕ [INDEX]
        this.append_view_column ("Name", 0, true);  // Моноширинный шрифт
        this.append_view_column ("Type", 1, true);  // Моноширинный шрифт
        this.append_view_column ("Value", 2, false); // Обычный текст

        // 4. Упаковываем в контейнер скроллинга [INDEX]
        this.scroll_window = new Gtk.ScrolledWindow ();
        this.scroll_window.set_child (this.tree_view);
        this.scroll_window.vexpand = true;
        this.append (this.scroll_window);

        // ===================================================================
        // ГЛАВНЫЙ СИГНАЛ ИСТИННОЙ ЛЕНИВОЙ ВЫКАЧКИ: [INDEX]
        // Вызывается строго в момент физического клика по стрелочке "▶"!
        // ===================================================================
        this.tree_view.row_expanded.connect (this.on_ui_row_expanded_lazy);

        // Подключаемся к сигналам центрального автомата отладки [INDEX]
        var dap_service = this.session.dap_service;
        dap_service.variables_updated.connect (this.on_variables_synchronized);
        dap_service.session_state_changed.connect (this.on_session_state_changed);
    }

    /**
     * ХEЛПEР СБOРКИ КОЛOНOК И РEНДEРEРOВ ТEКСТА [INDEX]
     */
    private void append_view_column (string title, int model_column_idx, bool use_monospace) {
        var renderer = new Gtk.CellRendererText ();
        renderer.xalign = 0.0f;
        
        if (use_monospace) {
            renderer.font = "Monospace 10";
        } else {
            renderer.ellipsize = Pango.EllipsizeMode.END;
        }

        var column = new Gtk.TreeViewColumn ();
        column.title = title;
        column.pack_start (renderer, true);
        
        // Напрямую связываем текстовое свойство рендерера с индексом в TreeStore! [INDEX]
        column.add_attribute (renderer, "text", model_column_idx);
        
        if (model_column_idx == 2) {
            column.expand = true; // Колонка "Значение" растягивается
        }

        this.tree_view.append_column (column);
    }

    /**
     * РEАКТИВНЫЙ ПEРEХВАТ РАСКРЫТИЯ СТРEЛOЧКИ ▶ (Ленивый сетевой пуш) [INDEX]
     */
    private void on_ui_row_expanded_lazy (Gtk.TreeIter parent_iter, Gtk.TreePath path) {
        GLib.Object raw_obj;
        this.tree_store.get (parent_iter, 3, out raw_obj, -1);
        
        var variable = raw_obj as DapVariable;
        if (variable == null || !variable.is_expandable () || variable.children_fetched) return;

        // Запускаем асинхронную транзакцию выкачки дочерних элементов в режиме fire-and-forget [INDEX]
        this.load_children_to_tree_node_async.begin (variable, parent_iter);
    }

    /**
     * АСИНХРОННЫЙ UI-МОСТ: Наполняет узел дерева без эффекта захлопывания ветки
     */
    private async void load_children_to_tree_node_async (DapVariable variable, Gtk.TreeIter parent_iter) {
        // Пинаем бэкенд выкачать дочерний массив переменных из дебаггера [INDEX]
        bool success = yield this.session.dap_service.fetch_variable_children_lazy_async (variable);
        
        if (success && variable.children != null) {
            // Переходим в UI-поток с низким приоритетом, чтобы дать GTK4 завершить анимацию клика! [INDEX]
            Idle.add_full (Priority.DEFAULT_IDLE, () => {
                
                // Блокируем сигналы TreeView на время модификации структуры, чтобы исключить мерцание
                this.tree_view.row_expanded.disconnect (this.on_ui_row_expanded_lazy);

                // 1. УДАЛЯEМ ЗАГЛУШКУ
                Gtk.TreeIter child_iter;
                if (this.tree_store.iter_children (out child_iter, parent_iter)) {
                    bool is_dummy;
                    this.tree_store.get (child_iter, 4, out is_dummy, -1);
                    
                    if (is_dummy) {
                        this.tree_store.remove (ref child_iter); // Удаляем "Loading..." [INDEX]
                    }
                }

                // 2. ВРEЗАEМ РEАЛЬНЫE ПEРEМEННЫE [INDEX]
                foreach (var child_var in variable.children) {
                    Gtk.TreeIter new_child;
                    this.tree_store.append (out new_child, parent_iter); 
                    
                    this.tree_store.set (new_child,
                        0, child_var.name,
                        1, child_var.type_label,
                        2, child_var.value_str,
                        3, child_var,
                        4, false,
                        -1
                    );

                    if (child_var.is_expandable ()) {
                        Gtk.TreeIter sub_dummy;
                        this.tree_store.append (out sub_dummy, new_child);
                        this.tree_store.set (sub_dummy, 0, "Loading...", 1, "", 2, "", 3, null, 4, true, -1);
                    }
                }

                // ===================================================================
                // ЖEЛEЗНОE ИСПРАВЛEНИE ДВOЙHОГO ТOГГЛА:
                // Получаем точный координатный путь текущего родительского узла в дереве
                // и ПРИHУДИТEЛЬHО командуем TreeView раскрыть его и зафиксировать на экране! [INDEX]
                // ===================================================================
                Gtk.TreePath parent_path = this.tree_store.get_path (parent_iter);
                this.tree_view.expand_row (parent_path, false); // false — раскрыть без рекурсии вглубь [INDEX]

                // Возвращаем на место живой мост прослушивания кликов
                this.tree_view.row_expanded.connect (this.on_ui_row_expanded_lazy);

                this.tree_view.queue_draw ();
                return Source.REMOVE;
            });
        }
    }

    /**
     * ОБHОВЛEНИE КOРHЯ ТАБЛИЦЫ ПРИ ШАГE ОТЛАДЧИКА (F10 / F11)
     */
    private void on_variables_synchronized (Gee.ArrayList<DapVariable> variables) {
        Idle.add_full (Priority.DEFAULT, () => {
            // Атомарно очищаем всё дерево [INDEX]
            this.tree_store.clear ();

            foreach (var v in variables) {
                Gtk.TreeIter root_iter;
                // Пушим переменные верхнего уровня (Locals) в корень дерева [INDEX]
                this.tree_store.append (out root_iter, null); 
                
                this.tree_store.set (root_iter,
                    0, v.name,
                    1, v.type_label,
                    2, v.value_str,
                    3, v,       // Привязываем объект DapVariable к строке таблицы! [INDEX]
                    4, false,   // Это реальный объект
                    -1
                );

                // ===================================================================
                // ЖEЛEЗНЫЙ ГАРАНТ ЭКСПАНДEРА ДЛЯ Gtk.TreeView:
                // Если переменная сложная, мы СРАЗУ добавляем к ней дочернюю строку-заглушку.
                // Увидев это, Gtk.TreeView СО СТОПРОЦЕНТНОЙ ГАРАНТИЕЙ нарисует стрелочку "▶"! [INDEX]
                // ===================================================================
                if (v.is_expandable ()) {
                    Gtk.TreeIter dummy_iter;
                    this.tree_store.append (out dummy_iter, root_iter); // Кладем внутрь root_iter! [INDEX]
                    this.tree_store.set (dummy_iter, 0, "Loading...", 1, "", 2, "", 3, null, 4, true, -1);
                }
            }
            return Source.REMOVE;
        });
    }

    private void on_session_state_changed (DapSessionState state, DapSessionState old_state) {
        if (state == DapSessionState.EMPTY) {
            Idle.add_full (Priority.DEFAULT, () => {
                this.tree_store.clear (); // Стираем память при завершении отладки
                return Source.REMOVE;
            });
        }
    }
}
