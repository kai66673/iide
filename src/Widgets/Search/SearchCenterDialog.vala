using Gtk;
using Adw;

public enum Iide.SearchPanelKind {
    FILES = 0,
    SYMBOL = 1,
    TEXT = 2
}

public class Iide.SearchCenterDialog : Adw.Window {
    private ViewStack view_stack;
    private ViewSwitcher view_switcher;
    private Window parent_window;
    private Iide.DocumentManager document_manager;

    private SearchPanelInterface[] search_pages;
    private string[,] pages_meta;

    public SearchCenterDialog (Window parent_window, Iide.DocumentManager document_manager) {
        Object (transient_for: parent_window, modal: true);
        this.parent_window = parent_window;
        this.document_manager = document_manager;
        set_default_size (600, 450);

        // Основной контейнер
        var content = new Box (Orientation.VERTICAL, 0);
        set_content (content);

        // Заголовок с переключателем вкладок
        var header_bar = new Adw.HeaderBar ();
        view_switcher = new ViewSwitcher ();
        header_bar.set_title_widget (view_switcher);
        content.append (header_bar);

        // Стек страниц поиска
        view_stack = new ViewStack ();
        view_switcher.stack = view_stack;
        content.append (view_stack);

        setup_pages ();
    }

    private void setup_pages () {
        search_pages = {
            new FuzzyFinderPage (parent_window, document_manager),
            new SearchSymbolPage (document_manager),
            new SearchInFilesPage (parent_window, document_manager),
        };

        pages_meta = {
            { "files", "Files", "document-open-symbolic" },
            { "symbols", "Symbols", "emblem-system-symbolic" },
            { "text", "Text", "edit-find-symbolic" },
        };

        for (var i = 0; i < 3; i++) {
            var panel = search_pages[i] as Gtk.Box;
            view_stack.add_titled (panel, pages_meta[i, 0], pages_meta[i, 1]);
            view_stack.get_page (panel).icon_name = pages_meta[i, 2];
        }

        foreach (var search_page in search_pages) {
            search_page.close_requested.connect_after (close);
        }

        view_stack.notify["visible-child"].connect_after (() => {
            SearchPanelInterface? active_page = view_stack.visible_child as SearchPanelInterface;
            if (active_page != null) {
                active_page.handle_activated ();
                active_page.focus_search_entry ();
            }
        });
    }

    // Метод для программного переключения вкладки (например, по Ctrl+Shift+O)
    public void set_active_page (SearchPanelKind panel_kind) {
        view_stack.visible_child_name = pages_meta[(int) panel_kind, 0];
        search_pages[(int) panel_kind].focus_search_entry ();
        search_pages[(int) panel_kind].handle_activated ();
    }
}
