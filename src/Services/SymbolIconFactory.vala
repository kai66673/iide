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
        _symbols_font_desc = Pango.FontDescription.from_string ("Symbols Nerd Font 11");
        _cached_attrs.insert (Pango.AttrFontDesc.new (_symbols_font_desc));
        _textures_cache = new Gee.HashMap<string, Gdk.Texture> ();

        _initialized = true;
    }

    /**
     * Создает виджет иконки на основе типа узла Tree-sitter (строка)
     */

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

    private static string filename_extension (string basename) {
        // Находим позицию последней точки
        int dot_index = basename.last_index_of_char ('.');
        if (dot_index != -1) {
            return basename.substring (dot_index);
        }
        return basename;
    }

    private static void get_file_info (GLib.File file, out string icon_char, out string color_hex) {
        string basename = file.get_basename ().down ();
        string extension = filename_extension (basename);

        switch (extension) {
        // --- Системные / Конфиги ---
        case "makefile": case ".mk":
            icon_char = "\ue673"; color_hex = "#6d8086";
            return;
        case "dockerfile": case ".dockerfile":
            icon_char = "\uf308"; color_hex = "#384d54";
            return;
        case ".json":
            icon_char = "\ue60b"; color_hex = "#cbcb41";
            return;
        case ".xml": case ".ui": case ".glade":
            icon_char = ((unichar) 0xf05c0).to_string (); color_hex = "#e37933";
            return;
        case ".yaml": case ".yml":
            icon_char = "\ue6a8"; color_hex = "#cb3e20";
            return;
        case ".conf": case ".ini":
            icon_char = "\ue615"; color_hex = "#6d8086";
            return;
        case ".md": case ".markdown":
            icon_char = "\ue609"; color_hex = "#519aba";
            return;
        case ".toml":
            icon_char = "\ue6b2"; color_hex = "#cb3e20";
            return;
        // --- Языки программирования ---
        case ".vala": case ".vapi":
            icon_char = "\ue69b"; color_hex = "#6e44b3";
            return;
        case ".c":
            icon_char = "\ue61e"; color_hex = "#599eff";
            return;
        case ".h": case ".hh": case ".hpp":
            icon_char = "\ue7fe"; color_hex = "#599eff";
            return;
        case ".cpp": case ".cc":
            icon_char = "\ue61d"; color_hex = "#00599c";
            return;
        case ".py": case ".pyi": case ".pyw":
            icon_char = "\ue73c"; color_hex = "#306998";
            return;
        case ".js":
            icon_char = "\ue74e"; color_hex = "#f1e05a";
            return;
        case ".ts":
            icon_char = "\ue628"; color_hex = "#2b7489";
            return;
        case ".css":
            icon_char = "\ue749"; color_hex = "#563d7c";
            return;
        case ".html":
            icon_char = "\ue736"; color_hex = "#e34c26";
            return;
        case ".sh": case ".zsh": case ".bash":
            icon_char = "\ue795"; color_hex = "#4ebd4e";
            return;
        case ".rs":
            icon_char = "\ue7a8"; color_hex = "#dea584";
            return;
        case ".go":
            icon_char = "\ue627"; color_hex = "#00add8";
            return;
        case ".lua":
            icon_char = "\ue620"; color_hex = "#000080";
            return;
        // --- Инструменты сборки ---
        case ".build":
            icon_char = "\ue673"; color_hex = "#8d9da4";
            return;
        }

        string mime = get_mime_type (file);

        // --- Мультимедиа (MIME-базировано) ---
        if (mime.has_prefix ("image/")) {
            icon_char = "\uf024f"; color_hex = "#a074c4";
        } else if (mime.has_prefix ("audio/") || mime.has_prefix ("video/")) {
            icon_char = "\uf024d"; color_hex = "#2b7489";
        } else if (mime == "application/pdf") {
            icon_char = "\uf1c1"; color_hex = "#cc342d";
        }

        // Значения по умолчанию
        icon_char = ((unichar) 0xf0214).to_string (); // (File)
        color_hex = "#858585"; // Gray
    }

    private static Gdk.Texture render_icon_to_texture (string icon_char, Gdk.RGBA color) {
        // Рендерим в Cairo Surface
        var surface = new Cairo.ImageSurface (Cairo.Format.ARGB32, TEXTURE_ICON_SIZE, TEXTURE_ICON_SIZE);
        var cr = new Cairo.Context (surface);

        Gdk.cairo_set_source_rgba (cr, color);

        // Настраиваем Pango Layout
        var layout = Pango.cairo_create_layout (cr);
        layout.set_font_description (_symbols_font_desc);
        layout.set_text (icon_char, icon_char.length);

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