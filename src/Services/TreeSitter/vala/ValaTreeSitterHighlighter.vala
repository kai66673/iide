using Gtk;
using GtkSource;

public class Iide.ValaTreeSitterHighlighter : OldBaseTreeSitterHighlighter {
    public ValaTreeSitterHighlighter (View view) {
        base (view);
        view.set_insert_spaces_instead_of_tabs (true);
        view.set_tab_width (4);
        view.set_smart_backspace (true);
    }

    protected override unowned TreeSitter.Language language () {
        return get_language_vala ();
    }

    protected override void highlight_node (TreeSitter.Node node) {
        switch (node.type ()) {
        case "comment":
            highlight_range (node, "def:comment");
            break;
        case "string":
        case "template_string":
            highlight_range (node, "def:string");
            break;
        case "integer":
            highlight_range (node, "def:floating-point");
            break;
        case "boolean":
            highlight_range (node, "def:boolean");
            break;
        case "identifier": {
            TextIter s_iter, e_iter;
            get_iters_from_ts_node (buffer, node, out s_iter, out e_iter);
            string node_text = buffer.get_text (s_iter, e_iter, false);
            if (node_text == "this" || node_text == "base") {
                highlight_range (node, "def:special-char");
            } else {
                highlight_range (node, "def:identifier");
            }
            break;
        }
        case "if":
        case "elif":
        case "else":
        case "switch":
        case "case":
        case "default":
            highlight_range (node, "c:type-keyword");
            break;
        case "for":
        case "foreach":
        case "while":
        case "do":
        case "break":
        case "continue":
            highlight_range (node, "c:type-keyword");
            break;
        case "class":
        case "interface":
        case "enum":
        case "struct":
            highlight_range (node, "c:type-keyword");
            break;
        case "public":
        case "private":
        case "protected":
        case "internal":
        case "static":
        case "virtual":
        case "override":
        case "abstract":
        case "sealed":
        case "async":
        case "const":
        case "ref":
        case "out":
        case "owned":
        case "unowned":
        case "weak":
            highlight_range (node, "c:type-keyword");
            break;
        case "void":
        case "bool":
        case "int":
        case "uint":
        case "int8":
        case "uint8":
        case "int16":
        case "uint16":
        case "int32":
        case "uint32":
        case "int64":
        case "uint64":
        case "size_t":
        case "ssize_t":
        case "float":
        case "double":
        case "var":
            highlight_range (node, "c:type-keyword");
            break;
        case "return":
        case "yield":
        case "try":
        case "catch":
        case "finally":
        case "throw":
            highlight_range (node, "c:type-keyword");
            break;
        case "namespace":
        case "using":
            highlight_range (node, "def:preprocessor");
            break;
        case "signal":
        case "construct":
        case "property":
            highlight_range (node, "c:printf");
            break;
        case "get":
        case "set":
        case "will":
        case "notify":
            highlight_range (node, "c:printf");
            break;
        case "in":
        case "is":
        case "as":
        case "typeof":
        case "sizeof":
        case "alignof":
        case "lock":
        case "throws":
        case "await":
        case "new":
        case "delete":
            highlight_range (node, "def:special-char");
            break;
        default:
            break;
        }
    }
}
