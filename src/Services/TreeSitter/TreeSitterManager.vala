// [CCode (cname = "tree_sitter_rust")]
// extern unowned TreeSitter.Language ? get_language_rust ();
// [CCode (cname = "tree_sitter_c")]
// extern unowned TreeSitter.Language ? get_language_c ();
// [CCode (cname = "tree_sitter_javascript")]
// extern unowned TreeSitter.Language ? get_language_javascript ();
// [CCode (cname = "tree_sitter_python")]
// extern unowned TreeSitter.Language ? get_language_python ();
// [CCode (cname = "tree_sitter_ruby")]
// extern unowned TreeSitter.Language ? get_language_ruby ();
// [CCode(cname = "tree_sitter_cpp")]
// extern unowned TreeSitter.Language ? get_language_cpp();
// [CCode(cname = "tree_sitter_vala")]
// extern unowned TreeSitter.Language ? get_language_vala();
// [CCode (cname = "tree_sitter_go")]
// extern unowned TreeSitter.Language ? get_language_go ();
// [CCode (cname = "tree_sitter_bash")]
// extern unowned TreeSitter.Language ? get_language_bash ();
// [CCode (cname = "tree_sitter_json")]
// extern unowned TreeSitter.Language ? get_language_json ();
// [CCode (cname = "tree_sitter_php")]
// extern unowned TreeSitter.Language ? get_language_php ();
// [CCode (cname = "tree_sitter_html")]
// extern unowned TreeSitter.Language ? get_language_html ();
// [CCode (cname = "tree_sitter_xml")]
// extern unowned TreeSitter.Language ? get_language_xml ();
// [CCode (cname = "tree_sitter_typescript")]
// extern unowned TreeSitter.Language ? get_language_typescript ();
// [CCode (cname = "tree_sitter_yaml")]
// extern unowned TreeSitter.Language ? get_language_yaml ();



class Iide.TreeSitterManager : GLib.Object {
    public BaseTreeSitterHighlighter ? get_ts_highlighter(SourceView view) {
        var language_name = ((GtkSource.Buffer) view.buffer).language.name.down();
        message("LANG Detected: " + language_name);
        switch (language_name) {
        case "cpp" :
            return new CppHighlighter(view);
        case "python":
            return new PythonHighlighter(view);
        case "rust":
            return new RustHighlighter(view);
        case "vala":
            return new ValaHighlighter(view);
        }
        return null;
    }

    // public unowned TreeSitter.Language? get_ts_language (GtkSource.Buffer buffer) {
    // var language_name = buffer.language.name.down ();
    // unowned TreeSitter.Language? language = null;
    // switch (language_name) {
    // case "bash" :
    // language = get_language_bash ();
    // break;
    // case "c" :
    // language = get_language_c ();
    // break;
    // case "cpp" :
    // language = get_language_cpp ();
    // break;
    // case "go" :
    // language = get_language_go ();
    // break;
    // case "javascript" :
    // language = get_language_javascript ();
    // break;
    // case "json" :
    // language = get_language_json ();
    // break;
    // case "html" :
    // language = get_language_html ();
    // break;
    // case "php" :
    // language = get_language_php ();
    // break;
    // case "python" :
    // language = get_language_python ();
    // break;
    // case "ruby" :
    // language = get_language_ruby ();
    // break;
    // case "rust" :
    // language = get_language_rust ();
    // break;
    // case "typescript" :
    // language = get_language_typescript ();
    // break;
    // case "xml" :
    // language = get_language_xml ();
    // break;
    // case "yaml" :
    // language = get_language_yaml ();
    // break;
    // }
    // return language;
    // }
}
