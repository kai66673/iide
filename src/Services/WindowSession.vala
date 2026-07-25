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
    public owned string get_project_name () { return current_project_root.get_basename (); }
    public owned string get_project_root_path () { return current_project_root.get_path (); }
    public owned GLib.File get_iide_dir () { return current_project_root.get_child (".iide"); }

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
    public TextLineMarkService[] marks_service { get; private set; }

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

        this.marks_service = { this.bookmark_service, this.breakpoint_service };

        // GTK-виджеты проекта
        this.grid = window.grid;
        this.dock = window.dock;
    }
}
