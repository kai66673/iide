/*
*/
public class Iide.TabSwitcherPopup : Gtk.Window {
    private Gtk.ListBox list_box;
    private int mru_list_size;
    private int current_index = 0;

    public TabSwitcherPopup (Gtk.Window parent_window, bool is_reverse) {
        Object (
            transient_for: parent_window, // Привязываем к главному окну приложения
            modal: true,                  // Блокируем ввод мимо переключателя, пока зажат Ctrl
            decorated: false,             // УБИРАЕМ РАМКИ (заголовки, кнопки закрытия — окно станет плоским!)
            resizable: false,
            title: "Tab Switcher"
        );
        this.add_css_class ("tab-switcher-popup");

        this.list_box = new Gtk.ListBox ();
        this.list_box.selection_mode = Gtk.SelectionMode.SINGLE;

        // Получаем очищенную от закрытых файлов MRU-историю
        var mru_list = DocumentManager.get_instance ().get_mru_history ();
        this.mru_list_size = mru_list.size;

        // Наполняем UI элементами в стиле двухстрочного списка Adwaita
        foreach (var source_view in mru_list) {
            // Извлекаем имя файла и полный путь к нему
            var file = File.new_for_uri (source_view.uri);
            string filename = file.get_basename () ?? "Untitled";
            string filepath = file.get_path () ?? source_view.uri;

            // Строка 1: Имя файла (Жирный шрифт)
            var title_label = new Gtk.Label (filename);
            title_label.halign = Gtk.Align.START;
            title_label.add_css_class ("title"); // Стандартный Adwaita-класс для жирного текста

            // Строка 2: Путь к файлу (Приглушенный мелкий текст)
            var path_label = new Gtk.Label (filepath);
            path_label.halign = Gtk.Align.START;
            path_label.add_css_class ("caption");   // Мелкий шрифт в GTK4
            path_label.add_css_class ("dim-label"); // Нативный серый цвет Adwaita

            // Упаковываем в вертикальный контейнер с отступом между строками в 2 пикселя
            var row_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 2);
            row_box.margin_start = 12;
            row_box.margin_end = 12;
            row_box.margin_top = 6;
            row_box.margin_bottom = 6;
            row_box.append (title_label);
            row_box.append (path_label);

            var row = new Gtk.ListBoxRow ();
            row.set_data("source-view", source_view);
            row.set_child (row_box);
            this.list_box.append (row);
        }

        var scrolled = new Gtk.ScrolledWindow ();
        scrolled.set_child (this.list_box);
        scrolled.set_size_request (640, 380);
        scrolled.max_content_height = 400;
        scrolled.propagate_natural_height = true;

        this.set_child (scrolled);

        // ===================================================================
        // ДИНАМИЧЕСКИЙ РАСЧЕТ СТАРТОВОГО ИНДЕКСА ДЛЯ MRU
        // ===================================================================
        if (this.mru_list_size > 1) {
            if (is_reverse) {
                // Если вызвали через Ctrl+Shift+Tab — сразу прыгаем на самый СТАРЫЙ документ
                this.current_index = this.mru_list_size - 1;
            } else {
                // Если вызвали через Ctrl+Tab — прыгаем на ПРЕДЫДУЩИЙ активный документ
                this.current_index = 1;
            }
        } else {
            this.current_index = 0;
        }

        this.select_row_at_index (this.current_index);

        // Добавляем контроллер клавиатуры СЮДА
        var popup_key_ctrl = new Gtk.EventControllerKey ();
        popup_key_ctrl.set_propagation_phase (Gtk.PropagationPhase.CAPTURE);

        // Обработка повторных нажатий (Tab / Shift+Tab) внутри окна
        popup_key_ctrl.key_pressed.connect ((keyval, keycode, state) => {
            var modifiers = state & (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.SHIFT_MASK);
            bool is_ctrl = (modifiers & Gdk.ModifierType.CONTROL_MASK) != 0;
            bool is_shift = (modifiers & Gdk.ModifierType.SHIFT_MASK) != 0;

            // Если при открытом окне продолжают нажимать Tab или ISO_Left_Tab (с зажатым Ctrl) [INDEX]
            if ((keyval == Gdk.Key.Tab || keyval == Gdk.Key.ISO_Left_Tab) && is_ctrl) {
                int direction = (is_shift || keyval == Gdk.Key.ISO_Left_Tab) ? -1 : 1;
                this.move_selection (direction); // Сдвигаем маркер выделения строки
                return true; // Глушим событие
            }

            return false;
        });

        // Слушаем отпускание клавиш внутри самого всплывающего окна
        popup_key_ctrl.key_released.connect ((keyval, keycode, state) => {
            if (keyval == Gdk.Key.Control_L || keyval == Gdk.Key.Control_R) {
                // Применяем выбор документа
                this.apply_selection ();
                
                // Закрываем и уничтожаем САМО СЕБЯ [INDEX]
                this.destroy (); 
            }
        });
        
        ((Gtk.Widget) this).add_controller (popup_key_ctrl);

        this.list_box.row_activated.connect ((row) => {
            var row_index = row.get_index ();
            if (this.current_index == row_index)
                return;
            this.current_index = row_index;
            this.apply_selection ();
        });
    }

    // Навигация по списку (+1 / -1)
    public void move_selection (int direction) {
        if (this.mru_list_size <= 1) return;

        this.current_index += direction;
        if (this.current_index >= this.mru_list_size) {
            this.current_index = 0;
        } else if (this.current_index < 0) {
            this.current_index = this.mru_list_size - 1;
        }

        this.select_row_at_index (this.current_index);
    }

    private void select_row_at_index (int index) {
        var row = this.list_box.get_row_at_index (index);
        if (row != null) {
            this.list_box.select_row (row);
            row.grab_focus ();
        }
        apply_selection ();
    }

    // Финальная активация выбранного документа
    public void apply_selection () {
        if (this.current_index >= 0 && this.current_index < this.mru_list_size) {
            var selected_row = this.list_box.get_row_at_index (this.current_index);
            SourceView selected_view = selected_row.get_data("source-view");
            
            // grab_focus() заставит libpanel автоматически поднять 
            // нужный фрейм и активировать нужную вкладку на экране
            var view_parent = selected_view.parent;
            while (view_parent != null) {
                var text_view = view_parent as TextView;
                if (text_view != null) {
                    text_view.raise ();
                    break;
                }
                view_parent = view_parent.parent;
            }
            selected_view.grab_focus ();
        }
    }
}

