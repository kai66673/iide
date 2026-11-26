public class Iide.SymbolsSearchEngine : SearchEngine, Object {
    private weak WindowSession session;
    
    public SymbolsSearchEngine (WindowSession session) {
        this.session = session;
    }

    public string search_entry_placeholder () {
        return _("Enter symbol name (min 3 chars)...");
    }

    public string search_progress_message () {
        return _("Searching symbols...");
    }

    public string search_kind () {
        return "symbols";
    }

    public string search_title () {
        return _("Symbols");
    }

    public string search_icon_name () {
        return "emblem-system-symbolic";
    }

    public async Gee.List<SearchResult> perform_search (string query, GLib.Cancellable cancellable) throws Error {
        var clients = this.session.lsp_service.get_clients ();
        var results = new Gee.ArrayList<WorkspaceLspSymbol> ();
        foreach (var client in clients) {
            // Сервер может не поддерживать workspace/symbol (например ruff —
            // он отвечает MethodNotFound -32601). Без проверки и try/catch
            // исключение от одного сервера уносило весь поиск: SearchPage
            // ловил его и показывал пустой список.
            if (!client.capabilities.workspace_symbol_provider)
                continue;

            Gee.List<WorkspaceLspSymbol>? syms = null;
            try {
                syms = yield client.workspace_symbols (query, cancellable);
            } catch (GLib.Error e) {
                if (cancellable.is_cancelled ())
                    throw e; // поиск снят новым запросом пользователя — выходим
                this.session.logger_service.warning ("SEARCH",
                    "Workspace symbol search failed on '%s': %s".printf (client.name (), e.message));
                continue;
            }

            if (syms != null)
                results.add_all (syms);
        }
        return to_search_results (results);
    }

    private Gee.List<SearchResult> to_search_results (Gee.List<WorkspaceLspSymbol> results) {
        var items = new Gee.ArrayList<SearchResult> ();
        foreach (var sym in results) {
            var file_path = sym.uri.replace ("file://", "");
            items.add (new SearchResult (
                                         file_path,
                                         file_path,
                                         sym.start_line,
                                         sym.name,
                                         null,
                                         ImageFactory.create_for_symbol (sym.kind)));
        }
        return items;
    }
}