public class Iide.TagPair : Object {
    public Gtk.TextTag light { get; construct; }
    public Gtk.TextTag dark { get; construct; }

    public TagPair (Gtk.TextTag l, Gtk.TextTag d) {
        Object (light: l, dark: d);
    }

    public Gtk.TextTag get_by_index (int index) {
        return (index == 0) ? light : dark;
    }
}

public class Iide.StyleService : Object {
    private static StyleService? instance;
    public Gtk.TextTagTable shared_table { get; private set; }

    // Теперь Gee.HashMap хранит объекты TagPair
    private Gee.HashMap<string, TagPair> registry;

    public static StyleService get_instance () {
        if (instance == null)instance = new StyleService ();
        return instance;
    }

    private StyleService () {
        shared_table = new Gtk.TextTagTable ();
        registry = new Gee.HashMap<string, TagPair> ();

        // --- Основы ---
        setup_tag ("function", "#1a5fb4", "#62a0ea", true);
        setup_tag ("keyword", "#a51d2d", "#ff7b72", true);
        setup_tag ("string", "#26a269", "#8ff0a4", false);
        setup_tag ("comment", "#5e5c64", "#94989b", false, true); // Italic
        setup_tag ("type", "#422d5b", "#f9c06b", true);
        setup_tag ("constant", "#986a44", "#d0b5f3", false);

        // --- Переменные и параметры ---
        setup_tag ("variable", "#241f31", "#ffffff", false);
        setup_tag ("variable.parameter", "#3584e4", "#78aeed", false);
        setup_tag ("variable.builtin", "#1a5fb4", "#62a0ea", false, true); // self, cls

        // --- Литералы и числа ---
        setup_tag ("number", "#3071db", "#78aeed", false);
        setup_tag ("boolean", "#986a44", "#d0b5f3", true);

        // --- Специальные элементы (Rust макросы, Vala атрибуты) ---
        setup_tag ("function.macro", "#63452c", "#c061cb", false);
        setup_tag ("attribute", "#63452c", "#c061cb", false);
        setup_tag ("label", "#422d5b", "#f9c06b", false); // Lifetimes в Rust ('a)

        // --- Пунктуация и операторы ---
        setup_tag ("operator", "#241f31", "#ffa348", false);
        setup_tag ("punctuation.bracket", "#241f31", "#d3d3d7", false);
        setup_tag ("punctuation.delimiter", "#241f31", "#d3d3d7", false);

        // --- Препроцессор и макросы (#include, #define, макросы в C/C++) ---
        setup_tag ("keyword.directive", "#63452c", "#c061cb", false);
        setup_tag ("keyword.control.import", "#63452c", "#c061cb", true);

        // --- Специфические для C++ (Namespace, Qualifier) ---
        setup_tag ("namespace", "#422d5b", "#f9c06b", false);
        setup_tag ("type.qualifier", "#a51d2d", "#ff7b72", false); // const, static, volatile

        // --- Дополнительные уточнения для функций ---
        setup_tag ("function.call", "#1c71d8", "#78aeed", false);
        setup_tag ("function.method", "#1a5fb4", "#62a0ea", true);

        // Тег для сброса (если в query есть @none)
        setup_tag ("none", null, null, false);
    }

    private void setup_tag (string name, string light_color, string dark_color, bool bold, bool italic = false) {
        // Создаем тег для светлой темы
        var tag_light = new Gtk.TextTag (name + ":light");
        tag_light.foreground = light_color;
        if (bold)tag_light.weight = Pango.Weight.BOLD;
        if (italic)tag_light.style = Pango.Style.ITALIC;
        shared_table.add (tag_light);

        // Создаем тег для темной темы
        var tag_dark = new Gtk.TextTag (name + ":dark");
        tag_dark.foreground = dark_color;
        if (bold)tag_dark.weight = Pango.Weight.BOLD;
        if (italic)tag_dark.style = Pango.Style.ITALIC;
        shared_table.add (tag_dark);

        // Сохраняем пару в реестр
        var pair = new TagPair (tag_light, tag_dark);
        registry.set (name, pair);
    }

    public Gtk.TextTag? get_tag (string name, int theme_index) {
        var pair = registry.get (name);
        if (pair != null) {
            return pair.get_by_index (theme_index);
        }
        return null;
    }
}
