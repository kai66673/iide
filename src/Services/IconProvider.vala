public class Iide.IconProvider {
    private static IconProvider? instance;
    private IconProvider() {}

    public static IconProvider get_instance() {
        if (instance == null) {
            instance = new IconProvider();
        }
        return instance;
    }

    public static string ? get_mime_type_icon_name(string mime_type) {
        switch (mime_type) {
        case "text/x-vala" :
            return "text-x-vala";
        case "text/x-meson":
            return "text-x-meson";
        case "text/markdown":
            return "text-markdown";
        }
        return "text-x-generic";
    }
}
