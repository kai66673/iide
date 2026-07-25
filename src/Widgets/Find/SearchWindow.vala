using Gtk;
using Adw;

public class Iide.SearchWindow : Adw.Window {
    private ViewStack view_stack;
    private ViewSwitcher view_switcher;
    private WindowSession parent_session;
    private Iide.DocumentManager document_manager;

    public SearchWindow (WindowSession parent_session, Iide.DocumentManager document_manager) {
        Object (transient_for: parent_session.window, modal: true);
        this.parent_session = parent_session;
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

        view_stack.notify["visible-child"].connect_after (() => {
            SearchPage? active_page = view_stack.visible_child as SearchPage;
            if (active_page != null) {
                active_page.handle_activated ();
            }
        });
    }

    private void setup_pages () {
        var fzf_search_page = new SearchPage (
            this.parent_session,
            new FzfSearchEngine (this.parent_session)
        );
        view_stack.add_titled_with_icon (
                                         fzf_search_page,
                                         fzf_search_page.search_kind (),
                                         fzf_search_page.search_title (),
                                         fzf_search_page.search_icon_name ());
        fzf_search_page.close_requested.connect_after (close);

        var symbols_search_page = new SearchPage (
            this.parent_session,
            new SymbolsSearchEngine (this.parent_session)
        );
        view_stack.add_titled_with_icon (
                                         symbols_search_page,
                                         symbols_search_page.search_kind (),
                                         symbols_search_page.search_title (),
                                         symbols_search_page.search_icon_name ());
        symbols_search_page.close_requested.connect_after (close);

        var text_search_page = new SearchPage (
            this.parent_session,
            new TextSearchEngine (this.parent_session)
        );
        view_stack.add_titled_with_icon (
                                         text_search_page,
                                         text_search_page.search_kind (),
                                         text_search_page.search_title (),
                                         text_search_page.search_icon_name ());
        text_search_page.close_requested.connect_after (close);
    }

    // Метод для программного переключения вкладки (например, по Ctrl+Shift+O)
    public void set_active_page (string search_kind) {
        var active_page = view_stack.get_child_by_name (search_kind) as SearchPage;
        if (active_page != null) {
            view_stack.visible_child = active_page;
            active_page.handle_activated ();
        }
    }
}