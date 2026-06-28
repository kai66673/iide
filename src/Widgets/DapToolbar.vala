/*
*/
public class Iide.DapToolbar : Gtk.Box {
    private LoggerService logger;
    private Gtk.DropDown target_drop_down;
    private Gtk.StringList target_string_list;

    private Gtk.Button start_continue_button;
    private Gtk.Button stop_button;
    private Gtk.Button step_over_button;
    private Gtk.Button step_into_button;
    private Gtk.Button step_out_button;

    private Gtk.Image start_continue_image;
    private bool is_populating_combo = false;

    public DapToolbar () {
        Object (orientation: Gtk.Orientation.HORIZONTAL, spacing: 0);
        this.logger = LoggerService.get_instance ();
        this.add_css_class ("linked"); // Склеит кнопки в единый монолитный блок
        this.valign = Gtk.Align.CENTER;

        // 1. Создаем строковую модель данных GTK4
        this.target_string_list = new Gtk.StringList (null);

        // 2. Инициализируем современный Gtk.DropDown, скармливая ему нашу модель
        this.target_drop_down = new Gtk.DropDown (this.target_string_list, null);
        this.target_drop_down.tooltip_text = "Select Debug Target";
        this.target_drop_down.valign = Gtk.Align.CENTER;

        // Подписываемся на смену выбора по спецификации GTK4 Properties Notification
        this.target_drop_down.notify["selected"].connect (this.on_target_selected_changed);
        this.append (this.target_drop_down);

        // 2. Кнопка Start / Continue (Зеленый треугольник)
        this.start_continue_button = new Gtk.Button ();
        this.start_continue_image = new Gtk.Image.from_icon_name ("media-playback-start-symbolic");
        this.start_continue_button.set_child (this.start_continue_image);
        this.start_continue_button.tooltip_text = "Start Debugging (F5)";
        this.start_continue_button.clicked.connect (this.on_start_continue_clicked);
        this.append (this.start_continue_button);

        // 3. Кнопка Stop (Красный квадрат)
        this.stop_button = new Gtk.Button.from_icon_name ("media-playback-stop-symbolic");
        this.stop_button.tooltip_text = "Stop Debugging (Shift+F5)";
        this.stop_button.clicked.connect (this.on_stop_clicked);
        this.append (this.stop_button);

        // 4. Кнопка Step Over (Шаг через)
        this.step_over_button = new Gtk.Button.from_icon_name ("go-next-symbolic");
        this.step_over_button.tooltip_text = "Step Over (F10)";
        this.step_over_button.clicked.connect (() => { DapService.get_instance ().trigger_step_over (); });
        this.append (this.step_over_button);

        // 5. Кнопка Step Into (Шаг в)
        this.step_into_button = new Gtk.Button.from_icon_name ("go-down-symbolic");
        this.step_into_button.tooltip_text = "Step Into (F11)";
        this.step_into_button.clicked.connect (() => { DapService.get_instance ().trigger_step_into (); });
        this.append (this.step_into_button);

        // 6. Кнопка Step Out (Шаг из)
        this.step_out_button = new Gtk.Button.from_icon_name ("go-up-symbolic");
        this.step_out_button.tooltip_text = "Step Out (Shift+F11)";
        this.step_out_button.clicked.connect (() => { DapService.get_instance ().trigger_step_out (); });
        this.append (this.step_out_button);

        // СВЯЗЫВАЕМ С БЭКЕНДОМ СИHГЛТОHОВ
        var dap_service = DapService.get_instance ();
        
        // А. Слушаем загрузку целей (событие открытия проекта)
        dap_service.configurations_loaded.connect (this.refresh_target_list);
        
        // Б. Реактивно слушаем конечный автомат состояний дебага!
        dap_service.session_state_changed.connect (this.sync_ui_with_state);

        // Первичная инициализация интерфейса в состояние "Покой"
        this.sync_ui_with_state (dap_service.session_state);
        this.refresh_target_list_on_idle ();
    }

    private void refresh_target_list_on_idle () {
        Idle.add (() => {
            this.refresh_target_list ();
            return Source.REMOVE;
        });
    }

    /**
     * СОВРЕМЕННОЕ ОБНОВЛЕНИЕ ЧЕРЕЗ ИЗМЕНЕНИЕ МОДЕЛИ Gtk.StringList
     */
    private void refresh_target_list () {
        this.is_populating_combo = true;
        
        // Начисто очищаем строковую модель данных
        this.target_string_list.splice (0, this.target_string_list.get_n_items (), null);

        var targets = DapService.get_instance ().get_targets ();
        
        if (targets.is_empty) {
            this.target_string_list.append ("No Targets Available");
            this.target_drop_down.selected = 0;
            this.sensitive = false; 
            this.is_populating_combo = false;
            return;
        }

        this.sensitive = true;
        foreach (var target in targets) {
            // Пушим строки в модель
            this.target_string_list.append (target.name);
        }

        // Выставляем первую цель активной в GTK4 DropDown
        this.target_drop_down.selected = 0;
        DapService.get_instance ().select_target (0);
        this.is_populating_combo = false;
    }

    /**
     * РЕАКЦИЯ НА ИЗМЕНЕНИЕ СВОЙСТВА "selected" В Gtk.DropDown
     */
    private void on_target_selected_changed (GLib.Object spec, GLib.ParamSpec pspec) {
        if (this.is_populating_combo) return;
        
        // В GTK4 свойство 'selected' возвращает uint индекс текущей строки
        uint active_idx = this.target_drop_down.selected;
        
        // Проверяем на GTK_INVALID_LIST_POSITION (который равен upper-limit uint, то есть G_MAXUINT)
        if (active_idx != uint.MAX) {
            DapService.get_instance ().select_target ((int) active_idx);
        }
    }

    /**
     * КHОПКА СТАРТ / ПРОДОЛЖИТЬ (F5)
     */
    private void on_start_continue_clicked () {
        var dap_service = DapService.get_instance ();

        if (dap_service.session_state == DapSessionState.EMPTY) {
            // Если отладчик выключен — извлекаем активную цель и запускаем сессию!
            var target = dap_service.get_active_target ();
            if (target == null) return;

            string workspace_root = ProjectManager.get_instance ().get_current_project_root ().get_path ();

            dap_service.start_debug_session_async.begin (target, workspace_root, (obj, res) => {
                dap_service.start_debug_session_async.end (res); 
            });
        } else if (dap_service.session_state == DapSessionState.BREAKPOINT) {
            // Если мы стоим на паузе — клик работает как команда "Continue" (Продолжить код)
            dap_service.trigger_continue ();
        }
    }

    private void on_stop_clicked () {
        DapService.get_instance ().stop_current_debug_session_async.begin ();
    }

    /**
        * РEАКТИВHАЯ СИHХРОHИЗАЦИЯ ДОСТУПHОСТИ КHОПОК С АВТОМАТОМ СEССИИ
        */
    private void sync_ui_with_state (DapSessionState state) {
        switch (state) {
            case DapSessionState.EMPTY:
                // СОСТОЯНИЕ: ПОКОЙ
                this.target_drop_down.sensitive = true; // Можно выбирать цели
                this.start_continue_button.sensitive = true;
                this.stop_button.sensitive = false;
                this.step_over_button.sensitive = false;
                this.step_into_button.sensitive = false;
                this.step_out_button.sensitive = false;

                // Кнопка работает как запуск: ставим обычную иконку старта
                this.start_continue_image.set_from_icon_name ("media-playback-start-symbolic");
                this.start_continue_button.tooltip_text = "Start Debugging (F5)";
                this.start_continue_button.remove_css_class ("suggested-action");
                this.stop_button.remove_css_class ("destructive-action");
                break;

            case DapSessionState.STARTED:
                // СОСТОЯНИЕ: ПРОГРАММА БEЖИТ В ОС (RUNNING)
                this.target_drop_down.sensitive = false; // Блокируем смену целей на ходу
                this.start_continue_button.sensitive = false; // Нельзя нажать Старт, пока код бежит
                this.stop_button.sensitive = true;   // Зато можно аварийно остановить!
                this.step_over_button.sensitive = false;
                this.step_into_button.sensitive = false;
                this.step_out_button.sensitive = false;

                this.start_continue_image.set_from_icon_name ("media-playback-start-symbolic");
                this.start_continue_button.remove_css_class ("suggested-action");
                this.stop_button.add_css_class ("destructive-action"); // Кнопка Стоп горит предупреждающим красным
                break;

            case DapSessionState.BREAKPOINT:
                // СОСТОЯНИЕ: МЫ НА ПАУЗE (PAUSED)
                this.target_drop_down.sensitive = false;
                this.start_continue_button.sensitive = true; // Разрешаем нажать "Continue"!
                this.stop_button.sensitive = true;
                
                // АКТИВИРУEМ ПОШАГОВОE ВЫПОЛHEHИE!
                this.step_over_button.sensitive = true;
                this.step_into_button.sensitive = true;
                this.step_out_button.sensitive = true;

                // МEHЯEМ СEМАHТИКУ КHОПКИ: теперь это кнопка Продолжить (зеленый Adwaita-акцент)
                this.start_continue_image.set_from_icon_name ("media-skip-forward-symbolic");
                this.start_continue_button.tooltip_text = "Continue Execution (F5)";
                this.start_continue_button.add_css_class ("suggested-action");
                this.stop_button.add_css_class ("destructive-action");
                break;
        }
    }
}
