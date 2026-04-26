public class Iide.SymbolsSearchEngine : SearchEngine, Object {

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
        var clients = IdeLspService.get_instance ().get_clients ();
        var results = new Gee.ArrayList<LspSymbol> ();
        foreach (var client in clients) {
            results.add_all (yield client.workspace_symbols (query, cancellable));
        }
        return to_search_results (results);
    }

    private Gee.List<SearchResult> to_search_results (Gee.List<LspSymbol> results) {
        var items = new Gee.ArrayList<SearchResult> ();
        foreach (var sym in results) {
            var file_path = sym.uri.replace ("file://", "");
            items.add (new SearchResult (
                                         file_path,
                                         file_path,
                                         sym.start_line,
                                         sym.name,
                                         null,
                                         SymbolIconFactory.create_for_symbol (sym.kind)));
        }
        return items;
    }
}