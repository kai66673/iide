public class Iide.SymbolIconFactory : Object {
    private static Pango.AttrList _cached_attrs;
    private static Pango.FontDescription _symbols_font_desc;
    private static Gee.HashMap<string, Gdk.Texture> _textures_cache;

    private static bool _initialized = false;

    private const int TEXTURE_ICON_SIZE = 16;

    private static void ensure_initialized () {
        if (_initialized)
            return;

        _cached_attrs = new Pango.AttrList ();
        // Размер 11pt обычно хорошо сочетается со стандартным шрифтом интерфейса
        _symbols_font_desc = Pango.FontDescription.from_string ("Symbols Nerd Font Mono 11");
        _cached_attrs.insert (Pango.AttrFontDesc.new (_symbols_font_desc));
        _textures_cache = new Gee.HashMap<string, Gdk.Texture> ();

        _initialized = true;
    }

    /**
     * Создает виджет иконки на основе типа узла Tree-sitter (строка)
     */

    public static Gtk.Widget create_for_ts (string type) {
        ensure_initialized ();

        string icon_char = "\uea8b"; // дефолтный символ
        Gdk.RGBA color = Gdk.RGBA () { red = 0.6f, green = 0.6f, blue = 0.58f, alpha = 1.0f }; // дефолтный серый

        // Мапинг для Tree-sitter
        if (type.contains ("class") || type.contains ("struct")) {
            icon_char = "\ueb5b";
            color.parse ("#f57900"); // orange
        } else if (type.contains ("method") || type.contains ("function")) {
            icon_char = "\uea8c";
            color.parse ("#9141ac"); // purple
        } else if (type.contains ("field") || type.contains ("variable") || type.contains ("parameter")) {
            icon_char = "\ueb5f";
            color.parse ("#3584e4"); // blue
        } else if (type.contains ("enum")) {
            icon_char = "\uea95";
            color.parse ("#f57900"); // orange
        } else if (type.contains ("interface")) {
            icon_char = "\ueb61";
            color.parse ("#33d17a"); // green
        }

        // Ключ кэша
        string key = @"ts:$icon_char:$(color.to_string())";

        if (!_textures_cache.has_key (key)) {
            _textures_cache.set (key, render_icon_to_texture (icon_char, color));
        }

        var img = new Gtk.Image.from_paintable (_textures_cache.get (key));
        img.pixel_size = 16;
        return img;
    }

    public static Gtk.Widget create_for_completion (Iide.IdeLspCompletionKind kind) {
        ensure_initialized ();

        string icon_char = "\uea8b"; // По умолчанию
        Gdk.RGBA color = Gdk.RGBA () { red = 0.6f, green = 0.6f, blue = 0.58f, alpha = 1.0f }; // Default gray (#9a9996)

        switch (kind) {
        case TEXT:
            icon_char = "\ueb69";
            break;
        case METHOD:
        case FUNCTION:
            icon_char = "\uea8c";
            color.parse ("#9141ac"); // purple
            break;
        case CONSTRUCTOR:
            icon_char = "\ueb44";
            color.parse ("#9141ac"); // purple
            break;
        case FIELD:
        case VARIABLE:
            icon_char = "\ueb5f";
            color.parse ("#3584e4"); // blue
            break;
        case CLASS:
            icon_char = "\ueb5b";
            color.parse ("#f57900"); // orange
            break;
        case INTERFACE:
            icon_char = "\ueb61";
            color.parse ("#2aa1b3"); // cyan
            break;
        case MODULE:
            icon_char = "\ueb29";
            color.parse ("#3584e4"); // blue
            break;
        case PROPERTY:
            icon_char = "\ueb65";
            color.parse ("#3584e4"); // blue
            break;
        case ENUM:
            icon_char = "\uea95";
            color.parse ("#f57900"); // orange
            break;
        case KEYWORD:
            icon_char = "\ueb62";
            break;
        case SNIPPET:
            icon_char = "\ueb66";
            color.parse ("#33d17a"); // green
            break;
        case COLOR:
            icon_char = "\ueb5c";
            color.parse ("#f9f06b"); // yellow
            break;
        case FILE:
            icon_char = "\uf0214";
            break;
        case FOLDER:
            icon_char = "\uf024b";
            color.parse ("#c0bfb1"); // tan/gray-gold
            break;
        case CONSTANT:
            icon_char = "\ueb5d";
            color.parse ("#3584e4"); // blue
            break;
        case STRUCT:
            icon_char = "\uea91";
            color.parse ("#f57900"); // orange
            break;
        case OPERATOR:
            icon_char = "\ueb64";
            color.parse ("#2aa1b3"); // cyan
            break;
        default:
            icon_char = "\uea8b";
            break;
        }

        // Ключ кэша
        string key = @"comp:$icon_char:$(color.to_string())";

        if (!_textures_cache.has_key (key)) {
            _textures_cache.set (key, render_icon_to_texture (icon_char, color));
        }

        var img = new Gtk.Image.from_paintable (_textures_cache.get (key));
        img.pixel_size = 16;
        return img;
    }

    public static Gtk.Widget create_for_symbol (Iide.SymbolKind kind) {
        ensure_initialized ();

        string icon_char;
        Gdk.RGBA color = Gdk.RGBA () { red = 0.6f, green = 0.6f, blue = 0.58f, alpha = 1.0f }; // Дефолтный серый (#9a9996)

        switch (kind) {
        case FILE:
            icon_char = "\uf0214";
            break;
        case MODULE:
        case NAMESPACE:
        case PACKAGE:
            icon_char = "\ueb29";
            color.parse ("#3584e4"); // blue
            break;
        case CLASS:
            icon_char = "\ueb5b";
            color.parse ("#f57900"); // orange
            break;
        case METHOD:
        case FUNCTION:
            icon_char = "\uea8c";
            color.parse ("#9141ac"); // purple
            break;
        case CONSTRUCTOR:
            icon_char = "\ueb44";
            color.parse ("#9141ac"); // purple
            break;
        case PROPERTY:
        case FIELD:
            icon_char = "\ueb65";
            color.parse ("#3584e4"); // blue
            break;
        case VARIABLE:
        case CONSTANT:
            icon_char = "\ueb5f";
            color.parse ("#3584e4"); // blue
            break;
        case STRING:
        case NUMBER:
        case BOOLEAN:
            icon_char = "\uea90";
            color.parse ("#33d17a"); // green
            break;
        case ENUM:
            icon_char = "\uea95";
            color.parse ("#f57900"); // orange
            break;
        case ENUM_MEMBER:
            icon_char = "\ueb5e";
            color.parse ("#3584e4"); // blue
            break;
        case STRUCT:
            icon_char = "\uea91";
            color.parse ("#f57900"); // orange
            break;
        case OPERATOR:
            icon_char = "\ueb64";
            color.parse ("#2aa1b3"); // cyan
            break;
        case TYPE_PARAMETER:
            icon_char = "\uea92";
            color.parse ("#2aa1b3"); // cyan
            break;
        default:
            icon_char = "\uea8b";
            break;
        }

        // Ключ кэша на основе символа и цвета
        string key = @"sym:$icon_char:$(color.to_string())";

        if (!_textures_cache.has_key (key)) {
            _textures_cache.set (key, render_icon_to_texture (icon_char, color));
        }

        var img = new Gtk.Image.from_paintable (_textures_cache.get (key));
        img.pixel_size = TEXTURE_ICON_SIZE;
        return img;
    }

    public static Gtk.Widget create_for_file (GLib.File file) {
        var texture = create_texture_for_file (file);
        var img = new Gtk.Image.from_paintable (texture);
        img.pixel_size = TEXTURE_ICON_SIZE;
        return img;
    }

    private static string get_mime_type (GLib.File file) {
        try {
            // Запрашиваем только нужный атрибут для скорости
            var info = file.query_info (FileAttribute.STANDARD_CONTENT_TYPE, FileQueryInfoFlags.NONE, null);
            var content_type = info.get_content_type ();
            return ContentType.get_mime_type (content_type);
        } catch (Error e) {
            return "application/octet-stream";
        }
    }

    private static void get_file_info (GLib.File file, out string icon_char, out string color_hex) {
        string name = file.get_basename ().down ();
        string mime = get_mime_type (file);

        // Значения по умолчанию
        icon_char = "\uf0214"; // (File)
        color_hex = "#858585"; // Gray

        if (mime == "inode/directory") {
            icon_char = "\uf024b"; // (Folder)
            color_hex = "#dcb67a"; // Tan
        }
        // --- Системные / Конфиги ---
        else if (name == "makefile" || name.has_suffix (".mk")) {
            icon_char = "\ue673"; color_hex = "#6d8086";
        } else if (name == "dockerfile" || name.has_suffix (".dockerfile")) {
            icon_char = "\uf308"; color_hex = "#384d54";
        } else if (name.has_suffix (".json")) {
            icon_char = "\ue60b"; color_hex = "#cbcb41";
        } else if (name.has_suffix (".xml") || name.has_suffix (".ui") || name.has_suffix (".glade")) {
            icon_char = "\uf05c0"; color_hex = "#e37933";
        } else if (name.has_suffix (".yaml") || name.has_suffix (".yml")) {
            icon_char = "\ue6a8"; color_hex = "#cb3e20";
        } else if (name.has_suffix (".conf") || name.has_suffix (".ini")) {
            icon_char = "\ue615"; color_hex = "#6d8086";
        } else if (name.has_suffix (".md") || name.has_suffix (".markdown")) {
            icon_char = "\ue609"; color_hex = "#519aba";
        }
        // --- Языки программирования ---
        else if (name.has_suffix (".vala") || name.has_suffix (".vapi")) {
            icon_char = "\ue69b"; color_hex = "#6e44b3";
        } else if (name.has_suffix (".c")) {
            icon_char = "\ue61e"; color_hex = "#599eff";
        } else if (name.has_suffix (".cpp") || name.has_suffix (".hpp") || name.has_suffix (".cc")) {
            icon_char = "\ue61d"; color_hex = "#00599c";
        } else if (name.has_suffix (".py")) {
            icon_char = "\ue73c"; color_hex = "#306998";
        } else if (name.has_suffix (".js")) {
            icon_char = "\ue74e"; color_hex = "#f1e05a";
        } else if (name.has_suffix (".ts")) {
            icon_char = "\ue628"; color_hex = "#2b7489";
        } else if (name.has_suffix (".css")) {
            icon_char = "\ue749"; color_hex = "#563d7c";
        } else if (name.has_suffix (".html")) {
            icon_char = "\ue736"; color_hex = "#e34c26";
        } else if (name.has_suffix (".sh") || name.has_suffix (".bash") || name.has_suffix (".zsh")) {
            icon_char = "\ue795"; color_hex = "#4ebd4e";
        } else if (name.has_suffix (".rs")) {
            icon_char = "\ue7a8"; color_hex = "#dea584";
        } else if (name.has_suffix (".go")) {
            icon_char = "\ue627"; color_hex = "#00add8";
        } else if (name.has_suffix (".lua")) {
            icon_char = "\ue620"; color_hex = "#000080";
        }
        // --- Инструменты сборки ---
        else if (name == "meson.build" || name == "meson_options.txt") {
            icon_char = "\ue673"; color_hex = "#8d9da4";
        } else if (name.has_suffix (".build")) { // Общий для разных сборок
            icon_char = "\ue673"; color_hex = "#8d9da4";
        }
        // --- Мультимедиа (MIME-базировано) ---
        else if (mime.has_prefix ("image/")) {
            icon_char = "\uf024f"; color_hex = "#a074c4";
        } else if (mime.has_prefix ("audio/") || mime.has_prefix ("video/")) {
            icon_char = "\uf024d"; color_hex = "#2b7489";
        } else if (mime == "application/pdf") {
            icon_char = "\uf1c1"; color_hex = "#cc342d";
        }
    }

    private static Gdk.Texture render_icon_to_texture (string icon_char, Gdk.RGBA color) {
        // Рендерим в Cairo Surface
        var surface = new Cairo.ImageSurface (Cairo.Format.ARGB32, TEXTURE_ICON_SIZE, TEXTURE_ICON_SIZE);
        var cr = new Cairo.Context (surface);

        Gdk.cairo_set_source_rgba (cr, color);

        // Настраиваем Pango Layout
        var layout = Pango.cairo_create_layout (cr);
        layout.set_font_description (_symbols_font_desc);
        layout.set_text (icon_char, -1);

        // Центрируем иконку
        Pango.Rectangle ink_rect, logical_rect;
        layout.get_pixel_extents (out ink_rect, out logical_rect);
        cr.move_to ((TEXTURE_ICON_SIZE - logical_rect.width) / 2.0,
                    (TEXTURE_ICON_SIZE - logical_rect.height) / 2.0);

        Pango.cairo_show_layout (cr, layout);

        size_t data_size = (size_t) surface.get_stride () * TEXTURE_ICON_SIZE;
        return new Gdk.MemoryTexture (TEXTURE_ICON_SIZE,
                                      TEXTURE_ICON_SIZE,
                                      Gdk.MemoryFormat.B8G8R8A8_PREMULTIPLIED,
                                      new Bytes (surface.get_data ()[0 : data_size]),
                                      surface.get_stride ());
    }

    public static Gdk.Texture create_texture_for_file (GLib.File file) {
        ensure_initialized ();

        // 1. Получаем данные об иконке (символ и цвет)
        string icon_char;
        string color_hex;
        get_file_info (file, out icon_char, out color_hex);

        // Ключ: символ + цвет + размер (если он будет меняться)
        string key = @"$icon_char:$color_hex";

        if (_textures_cache.has_key (key)) {
            return _textures_cache.get (key);
        }

        Gdk.RGBA rgba = {};
        rgba.parse (color_hex);
        var texture = render_icon_to_texture (icon_char, rgba);

        // Сохраняем в кэш
        _textures_cache.set (key, texture);

        return texture;
    }
}