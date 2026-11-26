/*
 * WindowSession.vala
 *
 * Контейнер всех проектных сервисов.
 * Один проект = одно окно = одна WindowSession.
 */

using Gtk;
using Panel;

public class Iide.WindowSession : Object {
    // Обратная ссылка на Window (нужна для UI: диалоги, grid, add_widget)
    public weak Iide.Window window { get; construct set; }

    // Корневая директория проекта (non-nullable — одно окно = один проект)
    public GLib.File current_project_root { get; set; }

    // Convenience-методы
    public string get_project_name () { return current_project_root.get_basename (); }
    public string get_project_root_path () { return current_project_root.get_path (); }
    public GLib.File get_iide_dir () { return current_project_root.get_child (".iide"); }

    // Список сервисов пометок (bookmarks + breakpoints) — метод, т.к. свойство
    // с массивным типом в GLib.Object не может быть GObject-свойством (предупреждение valac)
    public TextLineMarkService[] get_mark_services () { return marks_services; }

    // Сервисы проекта
    public LoggerService logger_service { get; construct set; }
    public LanguageRegistry language_registry { get; construct set; }
    public LspService lsp_service { get; construct set; }
    public DiagnosticsService diagnostics_service { get; construct set; }
    public DocumentManager document_manager { get; construct set; }
    public NavigationHistoryService navigation_history_service { get; construct set; }
    public ProjectManager project_manager { get; construct set; }
    public DapService dap_service { get; construct set; }
    public TextLineMarkService bookmark_service { get; construct set; }
    public TextLineMarkService breakpoint_service { get; construct set; }
    private TextLineMarkService[] marks_services;
    public FileOperationsService file_operations_service { get; construct set; }

    // GTK-виджеты проекта
    public Panel.Grid grid { get; construct set; }
    public Panel.Dock dock { get; construct set; }

    public WindowSession (Iide.Window window, GLib.File project_root) {
        this.window = window;
        this.current_project_root = project_root;

        this.logger_service = new LoggerService ();

        this.language_registry = new LanguageRegistry (this);

        this.lsp_service = new LspService (this);

        this.diagnostics_service = new DiagnosticsService (this);

        this.document_manager = new DocumentManager (this);

        this.navigation_history_service = new NavigationHistoryService (this);

        this.project_manager = new ProjectManager (this);

        this.dap_service = new DapService (this);

        this.bookmark_service = new BookmarksLineService (this, "bookmarks");

        this.breakpoint_service = new BreakpointsLineService (this, "breakpoints");

        this.marks_services = { this.bookmark_service, this.breakpoint_service };

        this.file_operations_service = new FileOperationsService (this);

        // GTK-виджеты проекта
        this.grid = window.grid;
        this.dock = window.dock;
    }
}
