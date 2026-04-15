[CCode (cname = "tree_sitter_cpp")]
extern unowned TreeSitter.Language ? get_lang_cpp ();

public class Iide.CppHighlighter : BaseTreeSitterHighlighter {
    public CppHighlighter (SourceView view) {
        base (view);
    }

    protected override unowned TreeSitter.Language get_ts_language () {
        return get_lang_cpp ();
    }

    protected override string get_query_filename () {
        return "cpp/highlights.scm";
    }

    protected override string query_source () {
        return """
        ; Functions

        (call_expression
          function: (qualified_identifier
            name: (identifier) @function))

        (template_function
          name: (identifier) @function)

        (template_method
          name: (field_identifier) @function)

        (template_function
          name: (identifier) @function)

        (function_declarator
          declarator: (qualified_identifier
            name: (identifier) @function))

        (function_declarator
          declarator: (field_identifier) @function)

        ; Types

        ((namespace_identifier) @type
         (#match? @type "^[A-Z]"))

        (auto) @type

        ; Constants

        (this) @variable.builtin
        (null "nullptr" @constant)

        ; Modules
        (module_name
          (identifier) @module)

        ; Keywords

        [
         "catch"
         "class"
         "co_await"
         "co_return"
         "co_yield"
         "constexpr"
         "constinit"
         "consteval"
         "delete"
         "explicit"
         "final"
         "friend"
         "mutable"
         "namespace"
         "noexcept"
         "new"
         "override"
         "private"
         "protected"
         "public"
         "template"
         "throw"
         "try"
         "typename"
         "using"
         "concept"
         "requires"
         "virtual"
         "import"
         "export"
         "module"
        ] @keyword

        ; Strings

        (raw_string_literal) @string
        """;
    }
}
