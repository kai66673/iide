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
        case "identifier":
            highlight_range(node, "def:identifier");
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
        case "with":
            highlight_range(node, "c:type-keyword");
            break;
        default:
            break;
        }
    }
}
