using Gtk;
using GtkSource;

[CCode (cname = "tree_sitter_cpp")]
extern unowned TreeSitter.Language ? get_language_cpp ();

public class Iide.CppTreeSitterHighlighter : OldBaseTreeSitterHighlighter {
    public CppTreeSitterHighlighter (View view) {
        base (view);
        view.set_insert_spaces_instead_of_tabs (true);
        view.set_tab_width (4);
        view.set_smart_backspace (true);
    }

    protected override unowned TreeSitter.Language language () {
        return get_language_cpp ();
    }

    protected override void highlight_node (TreeSitter.Node node) {
        switch (node.type ()) {
        case "identifier": {
            TextIter s_iter, e_iter;
            get_iters_from_ts_node (buffer, node, out s_iter, out e_iter);
            string node_text = buffer.get_text (s_iter, e_iter, false);
            switch (node_text) {
            case "auto":
            case "bool":
            case "char":
            case "double":
            case "float":
            case "int":
            case "long":
            case "short":
            case "signed":
            case "unsigned":
            case "void":
            case "wchar_t":
                highlight_range (node, "c:type-keyword");
                break;
            default:
                highlight_range (node, "def:identifier");
                break;
            }
            break;
        }
        case "and":
        case "and_eq":
        case "bitand":
        case "bitor":
        case "not":
        case "not_eq":
        case "or":
        case "or_eq":
        case "xor":
        case "xor_eq":
            highlight_range (node, "def:special-char");
            break;
        case "true":
        case "false":
            highlight_range (node, "def:boolean");
            break;
        case "string_literal":
            highlight_range (node, "def:string");
            break;
        case "number_literal":
            highlight_range (node, "def:floating-point");
            break;
        case "comment":
            highlight_range (node, "def:comment");
            break;
        case "preproc_directive":
        case "preproc_arg":
            highlight_range (node, "def:preprocessor");
            break;
        case "if":
        case "else":
        case "elif":
        case "while":
        case "for":
        case "do":
        case "switch":
        case "case":
        case "default":
        case "break":
        case "continue":
        case "return":
        case "goto":
            highlight_range (node, "c:type-keyword");
            break;
        case "class":
        case "struct":
        case "union":
        case "enum":
        case "namespace":
        case "typedef":
        case "using":
            highlight_range (node, "c:type-keyword");
            break;
        case "public":
        case "private":
        case "protected":
            highlight_range (node, "c:type-keyword");
            break;
        case "new":
        case "delete":
        case "this":
        case "operator":
        case "template":
        case "typename":
            highlight_range (node, "c:type-keyword");
            break;
        default:
            break;
        }
    }
}
