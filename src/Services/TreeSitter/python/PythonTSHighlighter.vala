[CCode (cname = "tree_sitter_python")]
extern unowned TreeSitter.Language ? get_lang_python ();

public class Iide.PythonHighlighter : BaseTreeSitterHighlighter {
  public PythonHighlighter (SourceView view) {
    base (view);
  }

  protected override unowned TreeSitter.Language get_ts_language () {
    return get_lang_python ();
  }

  protected override string get_query_filename () {
    return "python/highlights.scm";
  }

  protected override BaseTreeSitterIndenter ? create_indenter () {
    return new PythonTreeSitterIndenter (get_ts_language ());
  }

  protected override string query_source () {
    return """
        ; Identifier naming conventions

        (identifier) @variable

        ((identifier) @constructor
         (#match? @constructor "^[A-Z]"))

        ((identifier) @constant
         (#match? @constant "^[A-Z][A-Z_]*$"))

        ; Function calls

        (decorator) @function
        (decorator
          (identifier) @function)

        (call
          function: (attribute attribute: (identifier) @function.method))
        (call
          function: (identifier) @function)

        ; Builtin functions

        ((call
          function: (identifier) @function.builtin)
         (#match?
           @function.builtin
           "^(abs|all|any|ascii|bin|bool|breakpoint|bytearray|bytes|callable|chr|classmethod|compile|complex|delattr|dict|dir|divmod|enumerate|eval|exec|filter|float|format|frozenset|getattr|globals|hasattr|hash|help|hex|id|input|int|isinstance|issubclass|iter|len|list|locals|map|max|memoryview|min|next|object|oct|open|ord|pow|print|property|range|repr|reversed|round|set|setattr|slice|sorted|staticmethod|str|sum|super|tuple|type|vars|zip|__import__)$"))

        ; Function definitions

        (function_definition
          name: (identifier) @function)

        (attribute attribute: (identifier) @property)
        (type (identifier) @type)

        ; Literals

        [
          (none)
          (true)
          (false)
        ] @constant.builtin

        [
          (integer)
          (float)
        ] @number

        (comment) @comment
        (string) @string
        (escape_sequence) @escape

        (interpolation
          "{" @punctuation.special
          "}" @punctuation.special) @embedded

        [
          "-"
          "-="
          "!="
          "*"
          "**"
          "**="
          "*="
          "/"
          "//"
          "//="
          "/="
          "&"
          "&="
          "%"
          "%="
          "^"
          "^="
          "+"
          "->"
          "+="
          "<"
          "<<"
          "<<="
          "<="
          "<>"
          "="
          ":="
          "=="
          ">"
          ">="
          ">>"
          ">>="
          "|"
          "|="
          "~"
          "@="
          "and"
          "in"
          "is"
          "not"
          "or"
          "is not"
          "not in"
        ] @operators

        ["(" ")" "[" "]" "{" "}"] @punctuation.bracket

        [
          "as"
          "assert"
          "async"
          "await"
          "break"
          "class"
          "continue"
          "def"
          "del"
          "elif"
          "else"
          "except"
          "exec"
          "finally"
          "for"
          "from"
          "global"
          "if"
          "import"
          "lambda"
          "nonlocal"
          "pass"
          "print"
          "raise"
          "return"
          "try"
          "while"
          "with"
          "yield"
          "match"
          "case"
        ] @keyword
        """;
  }

  protected override bool is_container_node (string node_type) {
    return node_type in new string[] {
             "function_definition", "class_definition", "module_definition"
    };
  }
}