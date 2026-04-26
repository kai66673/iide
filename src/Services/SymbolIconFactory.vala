public class Iide.SymbolIconFactory : Object {
    private static Pango.AttrList _cached_attrs;
    private static bool _initialized = false;

    private static void ensure_initialized () {
        if (_initialized)return;

        _cached_attrs = new Pango.AttrList ();
        // Размер 11pt обычно хорошо сочетается со стандартным шрифтом интерфейса
        var font_desc = Pango.FontDescription.from_string ("Symbols Nerd Font Mono 11");
        _cached_attrs.insert (Pango.attr_font_desc_new (font_desc));

        _initialized = true;
    }

    /**
     * Создает виджет иконки на основе LSP SymbolKind (число)
     */
    public static Gtk.Widget create_for_lsp (int kind) {
        ensure_initialized ();

        string icon_char;
        string color_class;

        // Мапинг согласно стандарту LSP
        switch (kind) {
        case 1:  icon_char = "\uf0214"; color_class = "icon-gray";   break; // File
        case 5:  icon_char = "\ueb5b"; color_class = "icon-orange"; break; // Class
        case 6:  icon_char = "\uea8c"; color_class = "icon-purple"; break; // Method
        case 8:  icon_char = "\ueb5f"; color_class = "icon-blue";   break; // Field
        case 11: icon_char = "\uea8c"; color_class = "icon-purple"; break; // Function
        case 12: icon_char = "\uea8c"; color_class = "icon-purple"; break; // Method
        case 13: icon_char = "\ueb5f"; color_class = "icon-blue";   break; // Variable
        default: icon_char = "\uea8b"; color_class = "icon-gray";   break; // Default
        }

        return build_label (icon_char, color_class);
    }

    /**
     * Создает виджет иконки на основе типа узла Tree-sitter (строка)
     */
    public static Gtk.Widget create_for_ts (string type) {
        ensure_initialized ();

        string icon_char = "\uea8b";
        string color_class = "icon-gray";

        // Мапинг для Tree-sitter (пример для Vala/C)
        if (type.contains ("class")) {
            icon_char = "\ueb5b"; color_class = "icon-orange";
        } else if (type.contains ("method") || type.contains ("function")) {
            icon_char = "\uea8c"; color_class = "icon-purple";
        } else if (type.contains ("field") || type.contains ("variable")) {
            icon_char = "\ueb5f"; color_class = "icon-blue";
        }

        return build_label (icon_char, color_class);
    }

    public static Gtk.Widget create_for_completion (Iide.IdeLspCompletionKind kind) {
        ensure_initialized ();

        string icon_char = "\uea8b"; // По умолчанию (Misc)
        string color_class = "icon-gray";

        switch (kind) {
        case TEXT:        icon_char = "\ueb69"; color_class = "icon-gray"; break;
        case METHOD:
        case FUNCTION:    icon_char = "\uea8c"; color_class = "icon-purple"; break;
        case CONSTRUCTOR: icon_char = "\ueb44"; color_class = "icon-purple"; break;
        case FIELD:
        case VARIABLE:    icon_char = "\ueb5f"; color_class = "icon-blue"; break;
        case CLASS:       icon_char = "\ueb5b"; color_class = "icon-orange"; break;
        case INTERFACE:   icon_char = "\ueb61"; color_class = "icon-cyan"; break;
        case MODULE:      icon_char = "\ueb29"; color_class = "icon-blue"; break;
        case PROPERTY:    icon_char = "\ueb65"; color_class = "icon-blue"; break;
        case ENUM:        icon_char = "\uea95"; color_class = "icon-orange"; break;
        case KEYWORD:     icon_char = "\ueb62"; color_class = "icon-gray"; break;
        case SNIPPET:     icon_char = "\ueb66"; color_class = "icon-green"; break;
        case COLOR:       icon_char = "\ueb5c"; color_class = "icon-yellow"; break;
        case FILE:        icon_char = "\uf0214"; color_class = "icon-gray"; break;
        case FOLDER:      icon_char = "\uf024b"; color_class = "icon-tan"; break;
        case CONSTANT:    icon_char = "\ueb5d"; color_class = "icon-blue"; break;
        case STRUCT:      icon_char = "\uea91"; color_class = "icon-orange"; break;
        case OPERATOR:    icon_char = "\ueb64"; color_class = "icon-cyan"; break;
        default:          icon_char = "\uea8b"; color_class = "icon-gray"; break;
        }

        return build_label (icon_char, color_class);
    }

    public static Gtk.Widget create_for_symbol (Iide.SymbolKind kind) {
        ensure_initialized ();

        string icon_char = "\uea8b";
        string color_class = "icon-gray";

        switch (kind) {
        case FILE:           icon_char = "\uf0214"; color_class = "icon-gray"; break;
        case MODULE:
        case NAMESPACE:
        case PACKAGE:        icon_char = "\ueb29"; color_class = "icon-blue"; break;
        case CLASS:          icon_char = "\ueb5b"; color_class = "icon-orange"; break;
        case METHOD:
        case FUNCTION:       icon_char = "\uea8c"; color_class = "icon-purple"; break;
        case CONSTRUCTOR:    icon_char = "\ueb44"; color_class = "icon-purple"; break;
        case PROPERTY:
        case FIELD:          icon_char = "\ueb65"; color_class = "icon-blue"; break;
        case VARIABLE:
        case CONSTANT:       icon_char = "\ueb5f"; color_class = "icon-blue"; break;
        case STRING:
        case NUMBER:
        case BOOLEAN:        icon_char = "\uea90"; color_class = "icon-green"; break; // Объединим под "data"
        case ENUM:           icon_char = "\uea95"; color_class = "icon-orange"; break;
        case ENUM_MEMBER:    icon_char = "\ueb5e"; color_class = "icon-blue"; break;
        case STRUCT:         icon_char = "\uea91"; color_class = "icon-orange"; break;
        case OPERATOR:       icon_char = "\ueb64"; color_class = "icon-cyan"; break;
        case TYPE_PARAMETER: icon_char = "\uea92"; color_class = "icon-cyan"; break;
        default:             icon_char = "\uea8b"; color_class = "icon-gray"; break;
        }

        return build_label (icon_char, color_class);
    }

    public static Gtk.Widget create_for_file (GLib.File file) {
        ensure_initialized ();

        string icon_char = "\uf0214"; // По умолчанию: файл (  )
        string color_class = "icon-gray";

        string name = file.get_basename ().down ();
        string mime = get_mime_type (file);

        // 1. Сначала проверяем по MIME-типу
        if (mime == "inode/directory") {
            icon_char = "\uf024b"; //
            color_class = "icon-tan";
        } else if (mime.has_prefix ("image/")) {
            icon_char = "\uf024f"; //
            color_class = "icon-purple";
        } else if (mime.has_prefix ("video/") || mime.has_prefix ("audio/")) {
            icon_char = "\uf024d"; //
            color_class = "icon-cyan";
        } else if (mime == "application/pdf") {
            icon_char = "\uf1c1"; // 
            color_class = "icon-orange";
        } else if (mime == "application/x-executable" || mime == "application/x-sharedlib") {
            icon_char = "\ueb5a"; // 
            color_class = "icon-blue";
        }

        // 2. Уточняем по имени файла для языков программирования и инструментов
        // (Часто система выдает общий 'text/plain' для кода)
        if (name.has_suffix (".vala") || name.has_suffix (".vapi")) {
            icon_char = "\ue69b"; color_class = "icon-vala";
        } else if (name.has_suffix (".py")) {
            icon_char = "\ue73c"; color_class = "icon-blue";
        } else if (name.has_suffix (".c")) {
            icon_char = "\ue61e"; color_class = "icon-blue";
        } else if (name.has_suffix (".cpp") || name.has_suffix (".hpp") || name.has_suffix (".cc")) {
            icon_char = "\ue61d"; color_class = "icon-blue";
        } else if (name.has_suffix (".json")) {
            icon_char = "\ue60b"; color_class = "icon-yellow";
        } else if (name == "meson.build" || name == "meson_options.txt") {
            icon_char = "\ue673"; color_class = "icon-gray";
        } else if (name.has_suffix (".md")) {
            icon_char = "\ue609"; color_class = "icon-gray";
        } else if (name == "dockerfile" || name.has_suffix (".dockerfile")) {
            icon_char = "\uf308"; color_class = "icon-blue";
        }

        return build_label (icon_char, color_class);
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

    public static Gdk.Texture create_texture_for_file (GLib.File file) {
        ensure_initialized ();

        // 1. Получаем данные об иконке (символ и цвет)
        string icon_char;
        string color_hex;
        get_file_info (file, out icon_char, out color_hex);

        // 2. Рендерим в Cairo Surface
        int size = 16; // Стандартный размер иконки для вкладок/панелей
        var surface = new Cairo.ImageSurface (Cairo.Format.ARGB32, size, size);
        var cr = new Cairo.Context (surface);

        // Устанавливаем цвет
        Gdk.RGBA rgba = {};
        rgba.parse (color_hex);
        Gdk.cairo_set_source_rgba (cr, rgba);

        // Настраиваем Pango Layout
        var layout = Pango.cairo_create_layout (cr);
        layout.set_font_description (Pango.FontDescription.from_string ("Symbols Nerd Font Mono 11"));
        layout.set_text (icon_char, -1);

        // Центрируем иконку
        Pango.Rectangle ink_rect, logical_rect;
        layout.get_pixel_extents (out ink_rect, out logical_rect);
        cr.move_to ((size - logical_rect.width) / 2.0, (size - logical_rect.height) / 2.0);

        Pango.cairo_show_layout (cr, layout);

        // 3. Создаем текстуру из поверхности
        var pixbuf = Gdk.pixbuf_get_from_surface (surface, 0, 0, size, size);
        return Gdk.Texture.for_pixbuf (pixbuf);
    }

    private static Gtk.Widget build_label (string icon_char, string color_class) {
        var label = new Gtk.Label (icon_char);
        label.add_css_class ("nerd-icon");
        label.add_css_class (color_class);
        label.set_attributes (_cached_attrs);
        return label;
    }
}