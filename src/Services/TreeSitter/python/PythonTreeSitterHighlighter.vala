using Gtk;
using GtkSource;

[CCode(cname = "tree_sitter_python")]
extern unowned TreeSitter.Language ? get_language_python();

public class Iide.PythonTreeSitterHighlighter : BaseTreeSitterHighlighter {
    public PythonTreeSitterHighlighter(View view) {
        base(view);
    }

    protected override unowned TreeSitter.Language language() {
        return get_language_python();
    }

    protected override void highlight_node(TreeSitter.Node node) {
        // message(depth.to_string() + " " + parent_node?.type() + " -> " + node.type());
        switch (node.type()) {
        case "identifier": {
            TextIter s_iter, e_iter;
            get_iters_from_ts_node(buffer, node, out s_iter, out e_iter);
            string node_text = buffer.get_text(s_iter, e_iter, false);
            switch (node_text) {
            case "bool":
            case "int":
            case "float":
            case "complex":
            case "list":
            case "tuple":
            case "range":
            case "str":
            case "bytes":
            case "bytearray":
            case "memoryview":
            case "set":
            case "frozenset":
            case "dict":
            case "type":
            case "object":
                highlight_range(node, "python:builtin-function");
                break;
            default:
                highlight_range(node, "def:identifier");
                break;
            }
            break;
        }
        case "and":
        case "in":
        case "is":
        case "not":
        case "or":
        case "is not":
        case "not in":
        case "del":
            highlight_range(node, "def:special-char");
            break;
        case "none":
        case "true":
        case "false":
            highlight_range(node, "def:boolean");
            break;
        case "string":
            highlight_range(node, "def:string");
            break;
        case "integer":
            highlight_range(node, "def:floating-point");
            break;
        case "float":
            highlight_range(node, "def:floating-point");
            break;
        case "comment":
            highlight_range(node, "def:comment");
            break;
        case "import":
        case "from":
            highlight_range(node, "def:preprocessor");
            break;
        case "def":
        case "class":
        case "return":
        case "break":
        case "continue":
        case "if":
        case "else":
        case "elif":
        case "raise":
        case "while":
            highlight_range(node, "c:type-keyword");
            break;
        case "assert":
        case "exec":
        case "global":
        case "nonlocal":
        case "pass":
        case "print":
        case "with":
        case "as":
            highlight_range(node, "c:printf");
            break;
        default:
            break;
        }
    }
}
