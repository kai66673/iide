using Gtk;
using GtkSource;

[CCode (cname = "tree_sitter_python")]
extern unowned TreeSitter.Language ? get_language_python ();

public class Iide.PythonTreeSitterHighlighter : BaseTreeSitterHighlighter {
    public PythonTreeSitterHighlighter(View view) {
        base(view);
    }

    protected override unowned TreeSitter.Language language() {
        return get_language_python();
    }
}
