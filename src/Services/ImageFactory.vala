/*
 */

public class Iide.ImageFactory {
    public static Gtk.Widget create_for_ts (string type) {
        SymbIconProvider _provider = SymbIconProvider.get_instance ();

        // Мапинг для Tree-sitter
        if (type.contains ("class")) {
            return _provider.image (IconID.LS_CLASS);
        } else if (type.contains ("struct")) {
            return _provider.image (IconID.LS_STRUCT);
        } else if (type.contains ("method") || type.contains ("function")) {
            return _provider.image (IconID.LS_METHOD);
        } else if (type.contains ("field") || type.contains ("variable") || type.contains ("parameter")) {
            return _provider.image (IconID.LS_FIELD);
        } else if (type.contains ("enum")) {
            return _provider.image (IconID.LS_ENUM);
        } else if (type.contains ("interface")) {
            return _provider.image (IconID.LS_INTERFACE);
        }

        return _provider.image (IconID.LS_DEFAULT);
    }

    public static Gtk.Widget create_for_completion (Iide.IdeLspCompletionKind kind) {
        SymbIconProvider _provider = SymbIconProvider.get_instance ();

        switch (kind) {
        case TEXT:
            return _provider.image (IconID.LS_TEXT);
        case METHOD: case FUNCTION:
            return _provider.image (IconID.LS_METHOD);
        case CONSTRUCTOR:
            return _provider.image (IconID.LS_CONSTRUCTOR);
        case FIELD: case VARIABLE:
            return _provider.image (IconID.LS_FIELD);
        case CLASS:
            return _provider.image (IconID.LS_CLASS);
        case INTERFACE:
            return _provider.image (IconID.LS_INTERFACE);
        case MODULE:
            return _provider.image (IconID.LS_MODULE);
        case PROPERTY:
            return _provider.image (IconID.LS_PROPERTY);
        case ENUM:
            return _provider.image (IconID.LS_ENUM);
        case KEYWORD:
            return _provider.image (IconID.LS_KEYWORD);
        case SNIPPET:
            return _provider.image (IconID.LS_SNIPPET);
        case COLOR:
            return _provider.image (IconID.LS_COLOR);
        case FILE:
            return _provider.image (IconID.LS_FILE);
        case FOLDER:
            return _provider.image (IconID.LS_FOLDER);
        case CONSTANT:
            return _provider.image (IconID.LS_CONSTANT);
        case STRUCT:
            return _provider.image (IconID.LS_STRUCT);
        case OPERATOR:
            return _provider.image (IconID.LS_OPERATOR);
        default:
            return _provider.image (IconID.LS_DEFAULT);
        }
    }

    public static Gtk.Widget create_for_symbol (Iide.SymbolKind kind) {
        SymbIconProvider _provider = SymbIconProvider.get_instance ();

        switch (kind) {
        case FILE:
            return _provider.image (IconID.LS_FILE);
        case MODULE: case NAMESPACE: case PACKAGE:
            return _provider.image (IconID.LS_MODULE);
        case CLASS:
            return _provider.image (IconID.LS_CLASS);
        case METHOD: case FUNCTION:
            return _provider.image (IconID.LS_METHOD);
        case CONSTRUCTOR:
            return _provider.image (IconID.LS_CONSTRUCTOR);
        case PROPERTY: case FIELD:
            return _provider.image (IconID.LS_PROPERTY);
        case VARIABLE: case CONSTANT:
            return _provider.image (IconID.LS_CONSTANT);
        case STRING: case NUMBER: case BOOLEAN:
            return _provider.image (IconID.LS_LITERAL);
        case ENUM:
            return _provider.image (IconID.LS_ENUM);
        case ENUM_MEMBER:
            return _provider.image (IconID.LS_ENUM_MEMBER);
        case STRUCT:
            return _provider.image (IconID.LS_STRUCT);
        case OPERATOR:
            return _provider.image (IconID.LS_OPERATOR);
        case TYPE_PARAMETER:
            return _provider.image (IconID.LS_TYPE_PARAMETER);
        default:
            return _provider.image (IconID.LS_DEFAULT);
        }
    }

    public static Gtk.Image folder_image () {
        SymbIconProvider _provider = SymbIconProvider.get_instance ();
        return _provider.image (IconID.FOLDER);
    }

    private static string filename_extension (string basename) {
        // Находим позицию последней точки
        int dot_index = basename.last_index_of_char ('.');
        if (dot_index != -1) {
            return basename.substring (dot_index);
        }
        return basename;
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

    public static Gtk.Image create_for_file (GLib.File file) {
        SymbIconProvider _provider = SymbIconProvider.get_instance ();
        return _provider.image (icon_id_for_file (file));
    }

    public static Gtk.Image create_for_file_info (GLib.FileInfo info) {
        SymbIconProvider _provider = SymbIconProvider.get_instance ();
        return _provider.image (icon_id_for_file_info (info));
    }

    public static string icon_name_for_file (GLib.File file) {
        SymbIconProvider _provider = SymbIconProvider.get_instance ();
        return _provider.icon_name (icon_id_for_file (file));
    }

    private static IconID ? icon_id_for_extension (string extension) {
        switch (extension) {
        // --- Системные / Конфиги ---
        case "makefile" : case ".mk": case ".build":
            return IconID.MT_MAKE;
        case "dockerfile": case ".dockerfile":
            return IconID.MT_DOCKER;
        case ".json":
            return IconID.MT_JSON;
        case ".xml": case ".ui": case ".glade":
            return IconID.MT_XML;
        case ".yaml": case ".yml":
            return IconID.MT_YAML;
        case ".conf": case ".ini":
            return IconID.MT_INI;
        case ".md": case ".markdown":
            return IconID.MT_MD;
        case ".toml":
            return IconID.MT_TOML;
        // --- Языки программирования ---
        case ".vala": case ".vapi":
            return IconID.MT_VALA;
        case ".c":
            return IconID.MT_C;
        case ".h": case ".hh": case ".hpp":
            return IconID.MT_H;
        case ".cpp": case ".cc":
            return IconID.MT_CPP;
        case ".py": case ".pyi": case ".pyw":
            return IconID.MT_PY;
        case ".js":
            return IconID.MT_JS;
        case ".ts":
            return IconID.MT_TS;
        case ".css":
            return IconID.MT_CSS;
        case ".html":
            return IconID.MT_HTML;
        case ".sh": case ".zsh": case ".bash":
            return IconID.MT_BASH;
        case ".rs":
            return IconID.MT_RUST;
        case ".go":
            return IconID.MT_GO;
        case ".lua":
            return IconID.MT_MAKE;
        }
        return null;
    }

    private static IconID icon_id_for_file_info (GLib.FileInfo info) {
        string extension = filename_extension (info.get_name ());
        return icon_id_for_extension(extension) ?? IconID.MT_DEFAULT;
    }

    private static IconID icon_id_for_file (GLib.File file) {
        string basename = file.get_basename ().down ();
        string extension = filename_extension (basename);

        var icon_id = icon_id_for_extension (extension);
        if (icon_id != null) {
            return icon_id;
        }

        // --- Мультимедиа (MIME-базировано) ---
        string mime = get_mime_type (file);
        if (mime.has_prefix ("text/")) {
            return IconID.MT_X_TEXT;
        } else if (mime.has_prefix ("image/")) {
            return IconID.MT_X_IMAGE;
        } else if (mime.has_prefix ("audio/")) {
            return IconID.MT_X_AUDIO;
        } else if (mime.has_prefix ("video/")) {
            return IconID.MT_X_VIDEO;
        } else if (mime.has_prefix ("application/")) {
            return IconID.MT_X_APP;
        }

        return IconID.MT_DEFAULT;
    }
}