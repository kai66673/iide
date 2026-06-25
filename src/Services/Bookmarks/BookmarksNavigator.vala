/*
*/
public class Iide.BookmarksNavigator : GLib.Object {
    private static BookmarksNavigator? instance = null;

    public static BookmarksNavigator get_instance () {
        if (instance == null) {
            instance = new BookmarksNavigator ();
        }
        return instance;
    }

    public signal void document_bookmarks_changed(string file_uri, Gtk.TextBuffer buffer);
    public signal void goto_next_bookmark();
    public signal void goto_prev_bookmark();

    private BookmarksNavigator () {
        Object ();
    }
}
