public class Iide.IconProvider {
    private static IconProvider? instance;
    private Gtk.IconTheme icon_theme;
    private IconProvider() {
        icon_theme = Gtk.IconTheme.get_for_display(Gdk.Display.get_default());
        icon_theme.add_search_path("/usr/share/icons/Papirus");
    }

    public static IconProvider get_instance() {
        if (instance == null) {
            instance = new IconProvider();
        }
        return instance;
    }

    public static string ? get_mime_type_icon_name(string mime_type) {
        var gicon = GLib.ContentType.get_icon(mime_type);
        var self = get_instance();
        var icon_info = self.icon_theme.lookup_by_gicon(gicon, 48, 1, Gtk.TextDirection.LTR, 0);
        if (icon_info == null) {
            return null;
        }
        if (!icon_info.is_symbolic) {
            return null;
        }
        return icon_info.icon_name;
    }
}
