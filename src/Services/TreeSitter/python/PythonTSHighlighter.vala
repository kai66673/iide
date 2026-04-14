[CCode (cname = "tree_sitter_python")]
extern unowned TreeSitter.Language ? get_lang_python ();

public class Iide.PythonHighlighter : BaseTreeSitterHighlighter {
    public PythonHighlighter (SourceView view) {
        base (view);
        view.set_insert_spaces_instead_of_tabs (true);
        view.set_tab_width (4);
        view.set_smart_backspace (true);
    }

    protected override unowned TreeSitter.Language? get_ts_language () {
        return get_lang_python ();
    }

    protected override string get_query_filename () {
        return "python/highlights.scm";
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
        ] @operator

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

    // protected override string map_capture_to_gtk_tag (string capture_name) {
    //// Обработка сложных захватов из вашего highlights.scm
    // switch (capture_name) {
    //// Переменные и параметры
    // case "variable" :
    // case "variable.member":
    // return "def:identifier";
    // case "variable.parameter":
    // return "def:parameter"; // если в схеме нет, откатится к дефолту
    // case "variable.builtin": // self, cls
    // return "def:special-constant";

    //// Константы
    // case "constant":
    // case "constant.builtin":
    // case "boolean":
    // return "def:constant";

    //// Функции и методы
    // case "function":
    // case "function.call":
    // case "function.method":
    // case "function.method.call":
    // case "constructor":
    // return "def:function";
    // case "function.builtin":
    // return "def:builtin";

    //// Типы
    // case "type":
    // case "type.builtin":
    // case "type.definition":
    // return "def:type";

    //// Ключевые слова (разделенные на группы в вашем Query)
    // case "keyword":
    // case "keyword.function": // def, lambda
    // case "keyword.control": // if, else, match
    // case "keyword.repeat": // for, while
    // case "keyword.return": // return, yield
    // case "keyword.import": // import, from
    // case "keyword.exception": // try, except
    // case "keyword.conditional":
    // return "def:keyword";

    // case "keyword.operator": // and, in, is
    // return "def:operator";

    //// Строки и документация
    // case "string":
    // case "string.documentation":
    // case "string.escape":
    // return "def:string";

    //// Пунктуация и операторы
    // case "operator":
    // return "def:operator";
    // case "punctuation.bracket":
    // case "punctuation.delimiter":
    // case "punctuation.special":
    // return "def:bracket";

    // case "comment":
    // return "def:comment";

    // default:
    //// Если имя содержит точки (например, @variable.parameter),
    //// пробуем найти базовую категорию (variable)
    // if (capture_name.contains (".")) {
    // string base_cat = capture_name.split (".")[0];
    // return base.map_capture_to_gtk_tag (base_cat);
    // }
    // return base.map_capture_to_gtk_tag (capture_name);
    // }
    // }
}
