/*
*/
public enum Iide.DapSessionState {
    EMPTY,       // Отладчик не запущен, сессия пуста
    STARTED,     // Процесс отладки запущен и свободно выполняется в ОС (Running)
    BREAKPOINT   // Выполнение кода приостановлено на точке останова (Paused)
}

public class Iide.DapService : GLib.Object {
    public weak Window window;
    private static DapService? _instance = null;

    // Изолированные таблицы данных конфигураций, как вы и просили:
    private Gee.HashMap<string, DapConfig> adapters;     // Словарь DapConfig [adapter_id] -> [DapConfig]
    private Gee.ArrayList<DapTargetConfig> targets;     // Плоский список целей отладки
    
    private int selected_target_index = 0;
    private LoggerService logger;

    // Поле для хранения ID потока, на котором сейчас стоит пауза
    private int last_stopped_thread_id = 0;

    // Храним ID текущего кадра стека на паузе (нужен для evaluate)
    public int current_frame_id { get; private set; default = -1; }

    // Защитный затвор от бесконечного зацикливания сигналов
    private bool is_syncing_breakpoints = false;

    // Актуальный кэш локальных переменных текущей точки останова
    private Gee.ArrayList<DapVariable> local_variables = new Gee.ArrayList<DapVariable> ();

    // Кэш потоков текущей сессии останова
    private Gee.ArrayList<DapThread> current_threads = new Gee.ArrayList<DapThread> ();

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
                var old_state = this._session_state;
                this._session_state = value;
                // Извещаем UI-слой (кнопки панели, gutter, вкладки) о смене фазы отладки!
                Idle.add_full (Priority.DEFAULT, () => {
                    this.session_state_changed (value, old_state);
                    return Source.REMOVE; // Выполнить строго один раз
                });
            }
        }
    }

    // Сигналы вещания состояний для графического слоя IDE
    public signal void configurations_loaded ();
    public signal void session_state_changed (DapSessionState new_state, DapSessionState old_state);
    public signal void active_line_changed (string uri, int line_number); // Для подсветки строки останова
    public signal void console_output_append (string category, string text);

    // Сигнал для UI-панели переменных
    public signal void variables_updated (Gee.ArrayList<DapVariable> variables);
    // Сигнал для Call Stack панели
    public signal void threads_updated (Gee.ArrayList<DapThread> threads);
    // Сигнал смены активного кадра пользователем (для Variables View и подсветки строки)
    public signal void active_frame_changed (DapStackFrame frame);


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

    public Gee.ArrayList<DapVariable> get_local_variables () { return this.local_variables; }

    public Gee.ArrayList<DapTargetConfig> get_targets () { return this.targets; }

    public Gee.ArrayList<DapThread> get_current_threads () { return this.current_threads; }

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
            
            // В фоне запускаем асиннадцатый каскад размотки стека (fire-and-forget)
            this.locate_and_broadcast_active_line_async.begin (thread_id);
        });

        dap_client.output_received.connect ((category, text) => {
            // Пробрасываем сигнал вывода в UI-панель консоли
            this.console_output_append (category, text);
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

        this.init_breakpoints_live_sync_bridge ();

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
    
    /**
     * АСИНХРOННЫЙ КАСКАД OПРOСА СТEКА ДЛЯ UI ПОДСВEТКИ [INDEX]
     */
    private async void locate_and_broadcast_active_line_async (int thread_id) {
        if (this.current_client == null) return;

        try {
            // 1. Запрашиваем кадры стека у debugpy [INDEX]
            var stack_frames = yield this.current_client.request_stack_trace (thread_id);
            
            if (stack_frames != null && stack_frames.get_length () > 0) {
                // Извлекаем самый верхний (активный) кадр стека [INDEX]
                var top_frame = stack_frames.get_object_element (0);
                this.current_frame_id = (int) top_frame.get_int_member ("id"); // <-- ЗАПОМИНАЕМ ID КАДРА!

                // В DAP строки возвращаются 1-based [INDEX]!
                int dap_line = (int) top_frame.get_int_member ("line");
                
                var source_obj = top_frame.get_object_member ("source");
                if (source_obj != null && source_obj.has_member ("path")) {
                    string system_path = source_obj.get_string_member ("path");
                    
                    // Конвертируем абсолютный путь Linux обратно в каноничный URI для IDE
                    var file_obj = GLib.File.new_for_path (system_path);
                    string file_uri = file_obj.get_uri ();

                    this.logger.info ("DAP", @"Execution paused in file: $system_path at line: $dap_line");

                    // Меняем состояние сессии — это разблокирует кнопки тулбара через Idle.add
                    this.session_state = DapSessionState.BREAKPOINT;

                    // Мягко пинаем фоновое выкачивание переменных и stack-trace
                    this.fetch_variables_for_current_frame_async.begin ();
                    this.fetch_threads_on_stop_async.begin();

                    // Выстреливаем сигналом точных координат в UI поток!
                    // Переводим dap_line в 0-indexed для GTK редактора (делаем -1)
                    Idle.add (() => {
                        this.active_line_changed (file_uri, dap_line - 1);
                        return Source.REMOVE;
                    });
                }
            }
        } catch (GLib.Error e) {
            this.logger.error ("DAP", "Failed to resolve active stack frame location: " + e.message);
            this.session_state = DapSessionState.BREAKPOINT; // Все равно включаем панели
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
        this.disconnect_breakpoints_live_sync_bridge ();
        this.local_variables.clear ();
        this.current_threads.clear ();
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
        var array = new Json.Array ();
        array.add_string_element ("File \"([^\"]+)\", line (\\d+)");
        array.add_string_element ("([^\\s:]+):(\\d+):");
        py_obj.set_array_member ("outputLinkRegex", array);
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

    /**
     * ИНИЦИАЛИЗАЦИЯ ЖИВОГО МОСТА СИНХРОНИЗАЦИИ
     * Вызывается внутри start_debug_session_async строго ПОСЛЕ initialize,
     * но ДО первого flush_all_cached_breakpoints_to_server_async! [INDEX, INDEX]
     */
    private void init_breakpoints_live_sync_bridge () {
        this.window.breakpoint_service.uri_marks_changed.connect (this.on_ui_breakpoint_toggled_live);
    }

    /**
     * ОБРАБОТЧИК СИГНАЛА ИЗМEНEНИЯ МАРКEРОВ НА ПОЛЯХ
     */
    private void on_ui_breakpoint_toggled_live (string uri, Gee.ArrayList<TextLineMark?> marks) {
        // Защитный затвор: если изменение инициировано самой сетью — игнорируем,
        // предотвращая падение рантайма в бесконечную рекурсию!
        if (this.is_syncing_breakpoints)
            return;

        // Если отладчик выключен — горячий пуш не нужен, точки просто тихо живут в кэше сервиса [INDEX]
        if (this.current_client == null || this.session_state == DapSessionState.EMPTY)
            return;

        this.logger.info ("DAP", @"Hot-reloading breakpoints for modified layout: $uri");
        
        // Включаем асиннадцатый сетевой пуш в режиме fire-and-forget
        this.sync_single_file_breakpoints_live_async.begin (uri, marks);
    }

    /**
     * АСИНХРОННЫЙ ЖИВОЙ ПУШ ОБHОВЛEHHОГО МАССИВА СТРОК
     */
    private async void sync_single_file_breakpoints_live_async (string uri, Gee.ArrayList<TextLineMark?> marks) {
        if (this.current_client == null)
            return;

        var lines_to_push = new Gee.ArrayList<int> ();

        foreach (var mark in marks) {
            if (mark != null) {
                lines_to_push.add (mark.line_number);
            }
        }

        try {
            // Включаем защитный затвор перед отправкой по сети
            this.is_syncing_breakpoints = true;

            // 2. Выстреливаем монолитным пакетом setBreakpoints в сокет отладчика! [INDEX]
            // Внутри DapClient строки автоматически станут 1-based, а путь очистится через GLib.File [INDEX, INDEX]
            bool success = yield this.current_client.request_set_breakpoints (uri, lines_to_push);
            
            if (success) {
                this.logger.debug ("DAP", @"Network hot-reload confirmed for $uri.");
                
                // TODO: Если debugpy вернул смещенные строки (например, пользователь поставил точку 
                // на пустую строку, а Python сместил её на следующую инструкцию), 
                // здесь можно будет точечно обновить кэш TextLineMarkService.
            }

        } catch (GLib.Error e) {
            this.logger.error ("DAP", "Failed to hot-reload breakpoints over network: " + e.message);
        } finally {
            // ЖEЛEЗНO выключаем затвор в блоке finally, возвращая систему в рабочий режим!
            this.is_syncing_breakpoints = false;
        }
    }

    /**
     * ОЧИСТКА МОСТА ПРИ ЗАВЕРШЕНИИ СЕССИИ
     * Вызывается внутри cleanup_session_context()
     */
    private void disconnect_breakpoints_live_sync_bridge () {
        this.window.bookmark_service.uri_marks_changed.disconnect (this.on_ui_breakpoint_toggled_live);
        this.is_syncing_breakpoints = false;
    }

    /**
     * АСИНХРOHHЫЙ КАСКАД ВЫКАЧИВАНИЯ ПEРEМEHHЫХ ИЗ ПАМЯТИ
     * Вызывается внутри locate_and_broadcast_active_line_async СТРОГО ПОСЛЕ 
     * того, как мы успешно сохранили `this.current_frame_id = (int) top_frame.get_int_member ("id");`!
     */
    public async void fetch_variables_for_current_frame_async () {
        if (this.current_client == null || this.current_frame_id == -1) return;

        this.local_variables.clear ();

        try {
            // 1. Шаг А: Запрашиваем Scopes для текущего кадра стека
            var scopes_array = yield this.current_client.request_scopes (this.current_frame_id);
            if (scopes_array == null || scopes_array.get_length () == 0) return;

            int locals_reference = -1;

            // Перебираем области видимости, чтобы найти контейнер "Locals" (Локальные переменные)
            for (int i = 0; i < scopes_array.get_length (); i++) {
                var scope_obj = scopes_array.get_object_element (i);
                string scope_name = scope_obj.get_string_member ("name");

                // Нам интересны в первую очередь локальные переменные функции
                if (scope_name == "Locals" || scope_name == "Local") {
                    locals_reference = (int) scope_obj.get_int_member ("variablesReference");
                    break;
                }
            }

            // Если Locals не найден, возьмем первую попавшуюся область видимости в качестве фоллбэка
            if (locals_reference == -1) {
                var first_scope = scopes_array.get_object_element (0);
                locals_reference = (int) first_scope.get_int_member ("variablesReference");
            }

            // 2. Шаг Б: Запрашиваем сами переменные по полученной ссылке!
            if (locals_reference > 0) {
                var vars_array = yield this.current_client.request_variables (locals_reference);
                
                if (vars_array != null) {
                    for (int i = 0; i < vars_array.get_length (); i++) {
                        var var_obj = vars_array.get_object_element (i);
                        
                        string name = var_obj.get_string_member ("name");
                        string val = var_obj.get_string_member ("value");
                        string type = var_obj.has_member ("type") ? var_obj.get_string_member ("type") : "unknown";
                        int reference = (int) var_obj.get_int_member ("variablesReference");

                        // Заворачиваем в нашу модель и складываем в кэш сервиса
                        var variable_item = new DapVariable (name, val, type, reference);
                        this.local_variables.add (variable_item);
                    }
                }
            }

            this.logger.info ("DAP", @"Successfully fetched $(this.local_variables.size) local variables from frame context.");

            // 3. Выстреливаем сигналом в UI-поток для обновления виджета!
            Idle.add_full (Priority.DEFAULT, () => {
                this.variables_updated (this.local_variables);
                return Source.REMOVE;
            });

        } catch (GLib.Error e) {
            this.logger.error ("DAP", "Failed to fetch variables cascade: " + e.message);
        }
    }
    /**
     * ЛEНИВАЯ ВЫКАЧКА ДОЧEРНИХ ПEРEМEHHЫХ ПО СEТИ (Бэкенд-контроллер)
     */
    public async bool fetch_variable_children_lazy_async (DapVariable parent) {
        // Если объект нельзя раскрыть или данные уже у нас — выходим
        if (!parent.is_expandable () || parent.children_fetched)
            return true;
        if (this.current_client == null)
            return false;

        try {
            // Шлем запрос в сокет дебаггера
            var vars_array = yield this.current_client.request_variables (parent.variables_reference);
            
            if (vars_array != null && parent.children != null) {
                for (int i = 0; i < vars_array.get_length (); i++) {
                    var var_obj = vars_array.get_object_element (i);
                    
                    string name = var_obj.get_string_member ("name");
                    string val = var_obj.get_string_member ("value");
                    string type = var_obj.has_member ("type") ? var_obj.get_string_member ("type") : "unknown";
                    int reference = (int) var_obj.get_int_member ("variablesReference");

                    // Рождаем дочерний чистый объект
                    var child_var = new DapVariable (name, val, type, reference);
                    parent.children.add (child_var);
                }
            }
            
            parent.children_fetched = true;
            return true;
        } catch (GLib.Error e) {
            this.logger.error ("DAP", "Failed to fetch lazy sub-variables: " + e.message);
            return false;
        }
    }

    /**
     * КАСКАД 1: ПОЛУЧЕНИЕ ВСЕХ ПОТOКOВ ПРИ ОСТАНОВЕ (Вызывается из locate_and_broadcast_active_line_async)
     */
    public async void fetch_threads_on_stop_async () {
        if (this.current_client == null) return;
        this.current_threads.clear ();

        try {
            // Шлем запрос threads по спецификации DAP [INDEX]
            var reply = yield this.current_client.send_request ("threads", null);
            if (reply != null && reply.has_member ("success") && reply.get_boolean_member ("success")) {
                var body = reply.get_object_member ("body");
                if (body != null && body.has_member ("threads")) {
                    var threads_arr = body.get_array_member ("threads");
                    
                    for (int i = 0; i < threads_arr.get_length (); i++) {
                        var t_obj = threads_arr.get_object_element (i);
                        int id = (int) t_obj.get_int_member ("id");
                        string name = t_obj.get_string_member ("name");

                        this.current_threads.add (new DapThread (id, name));
                    }
                }
            }

            // Оповещаем панель Call Stack
            Idle.add_full (Priority.DEFAULT, () => {
                this.threads_updated (this.current_threads);
                return Source.REMOVE;
            });

        } catch (GLib.Error e) {
            this.logger.error ("DAP", "Failed to fetch threads: " + e.message);
        }
    }

    /**
     * КАСКАД 2: ЛЕНИВАЯ ВЫКАЧКА КАДРOВ СТЕКА ДЛЯ КОНКРЕТНОГO ПОТOКА (Вызывается при раскрытии ▶ в UI)
     */
    public async bool fetch_stack_frames_lazy_async (DapThread thread) {
        if (thread.stack_fetched || this.current_client == null) return true;

        try {
            var arguments = new Json.Object ();
            arguments.set_int_member ("threadId", thread.id);
            arguments.set_int_member ("levels", 20); // Запрашиваем до 20 уровней вложенности функций

            var reply = yield this.current_client.send_request ("stackTrace", arguments);
            if (reply != null && reply.has_member ("success") && reply.get_boolean_member ("success")) {
                var body = reply.get_object_member ("body");
                if (body != null && body.has_member ("stackFrames")) {
                    var frames_arr = body.get_array_member ("stackFrames");
                    
                    for (int i = 0; i < frames_arr.get_length (); i++) {
                        var f_obj = frames_arr.get_object_element (i);
                        int frame_id = (int) f_obj.get_int_member ("id");
                        string func_name = f_obj.get_string_member ("name");
                        int dap_line = (int) f_obj.get_int_member ("line");

                        string file_uri = "";
                        if (f_obj.has_member ("source")) {
                            var src_obj = f_obj.get_object_member ("source");
                            if (src_obj != null && src_obj.has_member ("path")) {
                                file_uri = GLib.File.new_for_path (src_obj.get_string_member ("path")).get_uri ();
                            }
                        }

                        // Сохраняем в DTO (переводим строку в 0-indexed для GTK) [INDEX]
                        var frame = new DapStackFrame (frame_id, func_name, file_uri, dap_line - 1);
                        thread.frames.add (frame);
                    }
                }
            }

            thread.stack_fetched = true;
            return true;
        } catch (GLib.Error e) {
            this.logger.error ("DAP", "Failed to fetch stack trace: " + e.message);
            return false;
        }
    }

    /**
     * СМЕНА КОНТЕКСТА КАДРА ПОЛЬЗОВАТЕЛЕМ (Клик на функцию в Call Stack)
     */
    public void switch_active_frame (DapStackFrame frame) {
        this.current_frame_id = frame.id; // Переключаем глобальный frameId!
        
        this.logger.info ("DAP", @"Switching context to frame: $(frame.function_name) (ID: $(frame.id))");
        
        // 1. Принудительно заставляем Variables View перевыкачать переменные для ЭТОЙ функции! [INDEX]
        this.fetch_variables_for_current_frame_async.begin ();

        // 2. Стреляем сигналом, чтобы MainWindow подсветил желтым строку именно этой функции! [INDEX]
        this.active_line_changed (frame.file_uri, frame.line);
    }
}
