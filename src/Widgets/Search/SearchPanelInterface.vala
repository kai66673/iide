public interface Iide.SearchPanelInterface : GLib.Object {
    public signal void close_requested();
    public abstract void focus_search_entry();
    public abstract void handle_activated();
}
