public interface Iide.SearchEngine : GLib.Object {
    public abstract string search_entry_placeholder ();
    public abstract string search_progress_message ();
    public abstract string search_kind ();
    public abstract string search_title ();
    public abstract string search_icon_name ();

    public abstract async Gee.List<SearchResult> perform_search (string query, GLib.Cancellable cancellable) throws Error;
}