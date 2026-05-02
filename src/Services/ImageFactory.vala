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
}