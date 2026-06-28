/*
*/
public enum Iide.DapSessionState {
    EMPTY,       // Отладчик не запущен, сессия пуста
    STARTED,     // Процесс отладки запущен и свободно выполняется в ОС (Running)
    BREAKPOINT   // Выполнение кода приостановлено на точке останова (Paused)
}

public class Iide.DapService : GLib.Object {
    public Window window;
    private static DapService? _instance = null;

    // Изолированные таблицы данных конфигураций, как вы и просили:
    private Gee.HashMap<string, DapConfig> adapters;     // Словарь DapConfig [adapter_id] -> [DapConfig]
    private Gee.ArrayList<DapTargetConfig> targets;     // Плоский список целей отладки
    
    private int selected_target_index = 0;
    private LoggerService logger;

    // Поле для хранения ID потока, на котором сейчас стоит пауза
    private int last_stopped_thread_id = 0;

    // ===================================================================
    // УПРАВЛЕНИЕ ЖИЗНЕННЫМ ЦИКЛОМ ТЕКУЩЕЙ СЕССИИ
    // ===================================================================
    // Сильная ссылка на активное семантическое ядро текущего дебаггера
    public DapClient? current_client { get; private set; default = null; }

    private DapSessionState _session_state = DapSessionState.EMPTY;
    public DapSessionState session_state {
        get { return this._session_state; }
        set {
            if (this._session_state != value) {
                this._session_state = value;
                // Извещаем UI-слой (кнопки панели, gutter, вкладки) о смене фазы отладки!
                Idle.add_full (Priority.DEFAULT, () => {
                    this.session_state_changed (value);
                    return Source.REMOVE; // Выполнить строго один раз
                });
            }
        }
    }

    // Сигналы вещания состояний для графического слоя IDE
    public signal void configurations_loaded ();
    public signal void session_state_changed (DapSessionState new_state);
    public signal void active_line_changed (string uri, int line_number); // Для подсветки строки останова

    public static DapService get_instance () {
        return _instance;
    }

    public DapService (Window window) {
        this.window = window;
        DapService._instance = this;
        this.adapters = new Gee.HashMap<string, DapConfig> ();
        this.targets = new Gee.ArrayList<DapTargetConfig> ();
        this.logger = LoggerService.get_instance ();

        // 1. Сразу при старте IDE в абсолютной тишине загружаем глобальный манифест отладчиков
        this.load_global_dap_manifest ();

        // 2. Биндим автоматическое чтение целей при открытии/закрытии папок проектов
        ProjectManager.get_instance ().project_opened.connect (this.load_project_launch_targets);
        ProjectManager.get_instance ().project_closed.connect (this.clear_project_targets);
    }

    public Gee.ArrayList<DapTargetConfig> get_targets () { return this.targets; }
    
    public DapTargetConfig? get_active_target () {
        if (this.targets.is_empty || selected_target_index >= this.targets.size) return null;
        return this.targets.get (selected_target_index);
    }

    public void select_target (int index) {
        if (index >= 0 && index < this.targets.size) this.selected_target_index = index;
    }

    /**
     * СВЯЗУЮЩИЙ УЗEЛ МАТРИЦЫ ОТЛАДКИ:
     * Вытаскивает из словаря системный профиль DapConfig для конкретной цели DapTargetConfig
     */
    public DapConfig? get_adapter_for_target (DapTargetConfig target) {
        if (this.adapters.has_key (target.adapter_id)) {
            return this.adapters.get (target.adapter_id);
        }
        return null;
    }

    /**
     * МEТОД 1: ЧТEНИE ГЛОБАЛЬНОГО СЛОВАРЯ DAP ИЗ ПРОФИЛЯ ПОЛЬЗОВАТEЛЯ
     */
    private void load_global_dap_manifest () {
        this.adapters.clear ();
        string config_path = Path.build_filename (Environment.get_home_dir (), ".config", "iide", "dap.json");
        var file = GLib.File.new_for_path (config_path);

        if (!file.query_exists ()) {
            this.logger.info ("DAP", "Global dap.json not found. Registering built-in python/lldb fallbacks...");
            this.register_built_in_fallbacks ();
            return;
        }

        try {
            var parser = new Json.Parser ();
            parser.load_from_file (config_path);
            var root = parser.get_root ().get_object ();
            
            if (root.has_member ("adapters")) {
                var adapters_obj = root.get_object_member ("adapters");
                foreach (var id in adapters_obj.get_members ()) {
                    var node = adapters_obj.get_object_member (id);
                    this.adapters.set (id, new DapConfig (id, node)); // Наполняем словарь DapConfig
                }
            }
            this.logger.info ("DAP", @"Registered $(this.adapters.size) global debug adapters inside dictionary.");
        } catch (GLib.Error e) {
            this.logger.error ("DAP", "Failed to parse global dap.json manifest: " + e.message);
            this.register_built_in_fallbacks ();
        }
    }

    /**
     * МEТОД 2: ЧТEНИE ЛОКАЛЬНОГО СПИСКА ЦEЛEЙ ИЗ ПАПКИ ПРОEКТА
     */
    private void load_project_launch_targets (GLib.File project_root) {
        this.clear_project_targets ();
        var file = project_root.get_child (".iide").get_child ("launch.json");
        
        if (!file.query_exists ()) {
            this.create_default_target ();
            return;
        }

        try {
            var parser = new Json.Parser ();
            parser.load_from_file (file.get_path ());
            var root = parser.get_root ().get_object ();
            
            if (root.has_member ("targets")) {
                var targets_array = root.get_array_member ("targets");
                foreach (var node in targets_array.get_elements ()) {
                    if (node.get_node_type () == Json.NodeType.OBJECT) {
                        this.targets.add (new DapTargetConfig (node.get_object ())); // Наполняем плоский список целей
                    }
                }
            }
            this.logger.info ("DAP", @"Successfully loaded $(this.targets.size) local debug targets from launch.json.");
        } catch (GLib.Error e) {
            this.logger.error ("DAP", "Failed to parse project launch.json: " + e.message);
            this.create_default_target ();
        }
        this.configurations_loaded ();
    }

    /**
     * ОПТИМИЗИРОВАННЫЙ ВЫТАСК ИЗ КЭША СEРВИСА ПРИ СТАРТE
     */
    private async void flush_all_cached_breakpoints_to_server_async () {
        if (this.current_client == null)
            return;
        
        this.logger.info ("DAP", "Flushing pre-registered UI breakpoints directly from TextLineMarkService cache...");
        
        // ОПТИМИЗАЦИЯ: Берем оригинальный, всегда актуальный registry хэш-мап вашего сервиса!
        var registry = this.window.breakpoint_service.get_registry ();

        foreach (var entry in registry.entries) {
            var file_marks = entry.value;
            if (file_marks == null || file_marks.is_empty)
                continue;
            
            var lines_to_push = new Gee.ArrayList<int> ();
            foreach (var mark in file_marks) {
                if (mark != null) lines_to_push.add (mark.line_number);
            }

            var uri = entry.key;
            if (!lines_to_push.is_empty) {
                try {
                    // Пушим пачку 0-indexed строк (внутри метода они сконвертируются в 1-based для DAP) [INDEX]
                    yield this.current_client.request_set_breakpoints (uri, lines_to_push);
                } catch (GLib.Error e) {
                    this.logger.error ("DAP", @"Failed to flush breakpoints for $uri: $(e.message)");
                }
            }
        }
    }

    /**
     * ВНУТРEННЯЯ ТРАНЗАКЦИЯ КОНФИГУРАЦИИ (Второй уровень матрешки) [INDEX]
     */
    private async void execute_dap_configuration_handshake_async (DapClient dap_client) {
        try {
            // 1. Сначала выталкиваем все брейкпоинты из кэша TextLineMarkService [INDEX]
            yield this.flush_all_cached_breakpoints_to_server_async ();

            // 2. И СРАЗУ ЖE шлем финальный пинок завершения конфигурации! [INDEX]
            // Это выведет debugpy из ступора, и он наконец вернет ответ на висящий на Первом Уровне запрос launch! [INDEX]
            yield dap_client.send_configuration_done_request ();
            
            this.logger.info ("DAP", "DAP Configuration handshake successfully completed on Level 2.");
        } catch (GLib.Error e) {
            this.logger.error ("DAP", "Failed to complete Level 2 DAP configuration: " + e.message);
        }
    }

    /**
     * ЦEНТРАЛЬНЫЙ АСИНХРОННЫЙ КОНВEЙEР ЗАПУСКА СEССИИ ОТЛАДКИ (F5)
     */
    public async bool start_debug_session_async (DapTargetConfig target, string workspace_root_path) {
        // Если сессия уже активна — запрещаем повторный запуск поверх!
        if (this.session_state != DapSessionState.EMPTY) {
            this.logger.warning ("DAP", "Cannot start a new debug session while one is already running.");
            return false;
        }
        // 1. Асинхронный UI-барьер сохранения изменений (без изменений)
        bool can_proceed = yield this.window.get_document_manager ().confirm_save_modified_documents_async ();
        if (!can_proceed)
            return false;

        // 2. Ищем Си-команду запуска отладчика ОС в нашем словаре по adapter_id цели
        var adapter_config = this.get_adapter_for_target (target);
        if (adapter_config == null) {
            this.logger.error ("DAP", @"No system DAP configuration found in dictionary for ID: '$(target.adapter_id)'");
            return false;
        }

        this.logger.info ("DAP", @"[Launch] Spawning process for adapter tool: '$(adapter_config.id)'...");

        // 2. Создаем DapClient (Семантическое ядро отладчика)
        var dap_client = new DapClient (adapter_config);
        bool spawned = yield dap_client.start_adapter_process_async (workspace_root_path);
        if (!spawned)
            return false;

        // ПОДКЛЮЧАЕМ СИГНАЛЫ КЛИЕНТА К НАШЕМУ СЕРВИСНОМУ АВТОМАТУ СОСТОЯНИЙ
        dap_client.stopped_on_breakpoint.connect ((thread_id, reason) => {
            // Переводим автомат в режим паузы на точке останова!
            this.session_state = DapSessionState.BREAKPOINT;
            this.last_stopped_thread_id = thread_id; // Запоминаем активный поток!
            
            // В реальном коде мы тут запросим stackTrace, чтобы понять, в каком файле и на какой строке замер код,
            // и выстрелим сигналом active_line_changed(uri, line) для подсветки строки в SourceView!
        });

        dap_client.terminated.connect (() => {
            // Отладчик завершил работу — полностью сбрасываем автомат
            this.cleanup_session_context ();
        });

        // ===================================================================
        // ВТОРОЙ РEАКТИВНЫЙ УРОВEНЬ (Внутренняя матрешка конфигурации)
        // Этот обработчик выстрелит изнутри недр выполнения запроса launch! [INDEX]
        // ===================================================================
        dap_client.adapter_ready_for_configuration.connect (() => {
            // Запускаем асинхронный пуш конфигурации в фоновом режиме fire-and-forget
            this.execute_dap_configuration_handshake_async.begin (dap_client);
        });

        this.current_client = dap_client;

        try {
            yield dap_client.send_initialize_request ();

            // 3. Вытаскиваем активный файл из DocumentManager для динамической замены макросов путей
            var source_view = this.window.get_active_source_view ();        
            string current_file_uri = source_view != null ? source_view.uri : "";

            // Разворачиваем пользовательские параметры (макросы, cwd, env) цели отладки!
            var processed_launch_args = target.get_processed_launch_params (current_file_uri, workspace_root_path);
            
            this.logger.info ("DAP", @"Sending processed launch configuration to '$(adapter_config.id)' сокет...");
            yield dap_client.send_launch_request (processed_launch_args);
            
            // ЗАПУСК УСПЕШЕН: Сохраняем ссылку и переводим автомат в статус РАБОТАEТ (STARTED)
            this.session_state = DapSessionState.STARTED;
            this.logger.info ("DAP", @"launch configuration '$(adapter_config.id)' done...");

            return true;
        } catch (GLib.Error e) {
            // Если вылетела сетевая ошибка (или отмена) на любом шаге — 
            // гарантированно тушим созданный процесс, освобождая Си-дескрипторы ОС!
            this.logger.error ("DAP", @"Critical error during debug session handshake: $(e.message)");
            
            dap_client.status = DapClientStatus.FAILED;
            
            // Асинхронно рвем каналы транспорта, чтобы не плодить зомби-процессы в Linux
            yield dap_client.disconnect_and_stop_async ();
            return false;
        }
    }

    public void trigger_continue () {
        if (this.current_client == null || this.session_state != DapSessionState.BREAKPOINT) return;
        
        // Программа оживает — переводим автомат в STARTED
        this.session_state = DapSessionState.STARTED;

        this.current_client.request_continue.begin (this.last_stopped_thread_id, (obj, res) => {
            try { this.current_client.request_continue.end (res); } catch {}
        });
    }

    public void trigger_step_over () {
        if (this.current_client == null || this.session_state != DapSessionState.BREAKPOINT) return;
        this.session_state = DapSessionState.STARTED;

        this.current_client.request_step_over.begin (this.last_stopped_thread_id, (obj, res) => {
            try { this.current_client.request_step_over.end (res); } catch {}
        });
    }

    public void trigger_step_into () {
        if (this.current_client == null || this.session_state != DapSessionState.BREAKPOINT) return;
        this.session_state = DapSessionState.STARTED;

        this.current_client.request_step_into.begin (this.last_stopped_thread_id, (obj, res) => {
            try { this.current_client.request_step_into.end (res); } catch {}
        });
    }

    public void trigger_step_out () {
        if (this.current_client == null || this.session_state != DapSessionState.BREAKPOINT) return;
        this.session_state = DapSessionState.STARTED;

        this.current_client.request_step_out.begin (this.last_stopped_thread_id, (obj, res) => {
            try { this.current_client.request_step_out.end (res); } catch {}
        });
    }

    /**
     * ПРИНУДИТEЛЬНОE ЗУШEНИE ТEКУЩEЙ СEССИИ ОТЛАДКИ (Кнопка Стоп на панели)
     */
    public async void stop_current_debug_session_async () {
        if (this.current_client == null)
            return;

        this.logger.info ("DAP", "Requesting manual debug session termination...");
        yield this.current_client.disconnect_and_stop_async ();
        this.cleanup_session_context ();
    }

    /**
     * Полная стерилизация контекста сессии при завершении дебага
     */
    private void cleanup_session_context () {
        this.current_client = null;
        this.session_state = DapSessionState.EMPTY;
        this.logger.info ("DAP", "Debug session context cleared cleanly.");
    }

    private void register_built_in_fallbacks () {
        var py_obj = new Json.Object ();
        var py_cmd = new Json.Array ();
        py_cmd.add_string_element ("python3");
        py_cmd.add_string_element ("-m");
        py_cmd.add_string_element ("debugpy.adapter");
        py_obj.set_array_member ("command", py_cmd);
        py_obj.set_string_member ("transport", "stdio");
        this.adapters.set ("python-local", new DapConfig ("python-local", py_obj));

        var lldb_obj = new Json.Object ();
        var lldb_cmd = new Json.Array ();
        lldb_cmd.add_string_element ("lldb-dap");
        lldb_obj.set_array_member ("command", lldb_cmd);
        lldb_obj.set_string_member ("transport", "stdio");
        this.adapters.set ("lldb-native", new DapConfig ("lldb-native", lldb_obj));
    }

    private void create_default_target () {
        var t_obj = new Json.Object ();
        t_obj.set_string_member ("name", "Python: Current File (Auto)");
        t_obj.set_string_member ("adapter_id", "python-local");
        t_obj.set_string_member ("program", "${file}");
        this.targets.add (new DapTargetConfig (t_obj));
        this.selected_target_index = 0;
        this.configurations_loaded ();
    }

    private void clear_project_targets () {
        this.targets.clear ();
        this.selected_target_index = 0;
    }
}
