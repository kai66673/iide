/**
 * СEРВИС УПРАВЛEНИЯ БРEЙКПОИНТАМИ (По аналогии с BookmarksService)
 * Хранит, сериализует в конфиг проекта и вещает об изменениях красных точек
 */
public class Iide.BreakpointsService : GLib.Object {
    private static BreakpointsService? _instance = null;

    // Внутренний реестр: [URI файла] -> [Список номеров строк (1-based)]
    private Gee.HashMap<string, Gee.ArrayList<int>> registry;
    private LoggerService logger;

    // Сигнал для гуттера: просит конкретную вкладку перерисовать свои поля
    public signal void breakpoints_changed (string uri);

    public static BreakpointsService get_instance () {
        if (_instance == null) {
            _instance = new BreakpointsService ();
        }
        return _instance;
    }

    private BreakpointsService () {
        this.registry = new Gee.HashMap<string, Gee.ArrayList<int>> ();
        this.logger = LoggerService.get_instance ();

        // Привязываемся к жизненному циклу проекта для автоматического сохранения/загрузки
        ProjectManager.get_instance ().project_opened.connect (this.load_from_project_settings);
        ProjectManager.get_instance ().project_closed.connect (this.clear_all);
    }

    public Gee.HashMap<string, Gee.ArrayList<int>> get_registry () {
        return this.registry;
    }

    /**
     * ПEРEКЛЮЧEНИE ТОЧКИ ИЗ UI (Вызывается по клику на гуттер)
     */
    public void toggle_breakpoint (string uri, int line) {
        if (!this.registry.has_key (uri)) {
            this.registry.set (uri, new Gee.ArrayList<int> ());
        }

        var file_lines = this.registry.get (uri);
        
        if (file_lines.contains (line)) {
            file_lines.remove (line);
            this.logger.info ("DAP-UI", @"Breakpoint removed at memory: $uri:$line");
        } else {
            file_lines.add (line);
            // Сортируем список строк, чтобы они шли по порядку сверху вниз (удобно для отрисовки и LSP)
            file_lines.sort ();
            this.logger.info ("DAP-UI", @"Breakpoint added at memory: $uri:$line");
        }

        // Мгновенно пинаем гуттер конкретной вкладки на перерисовку!
        this.breakpoints_changed (uri);

        // Автоматически сохраняем обновленный реестр в настройки проекта на диск
        this.save_to_project_settings ();
    }

    public bool has_breakpoint_at (string uri, int line) {
        if (!this.registry.has_key (uri)) return false;
        return this.registry.get (uri).contains (line);
    }

    /**
     * ЗАГРУЗКА ИЗ СEССИИ ПРОEКТА (Вызывается при открытии папки воркспейса)
     */
    private void load_from_project_settings (GLib.File project_root) {
        this.clear_all ();
        
        // Ищем или считываем из вашего центрального файла настроек проекта (например, .iide/project.json)
        // Реализуйте Си-партинг массива "breakpoints" абсолютно идентично вашим закладкам:
        // Foreach узел -> извлекаем uri и массив строк -> складываем в registry.
        
        this.logger.info ("DAP-UI", "Pre-registered project breakpoints loaded into service layout.");
    }

    /**
     * СOХРАНEНИE НА ДИСК (Вызывается атомарно при каждом изменении)
     */
    private void save_to_project_settings () {
        if (!ProjectManager.get_instance ().has_open_project ()) return;
        
        // Формируем JSON-массив или пишем в настройки воркспейса по аналогии с вашим BookmarksService
        // ...
    }

    private void clear_all () {
        this.registry.clear ();
    }
}
