namespace Iide {
    // Делегат для передачи пачки результатов
    public delegate void SearchResultsBatchFunc (SearchResult[] results);

    // Основной интерфейс плагина
    public interface SearchExtension : GLib.Object {
        public abstract async void run_search (string query,
            SearchResultsBatchFunc callback,
            GLib.Cancellable? cancellable) throws GLib.Error;
    }
}
