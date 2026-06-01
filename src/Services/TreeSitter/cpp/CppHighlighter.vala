[CCode (cname = "tree_sitter_cpp")]
extern unowned TreeSitter.Language ? get_lang_cpp ();

public class Iide.CppHighlighter : BaseTreeSitterHighlighter {
    public CppHighlighter (SourceView view) {
        base (view);
    }

    protected override unowned TreeSitter.Language get_ts_language () {
        return get_lang_cpp ();
    }

    protected override string query_source () {
        return """
[
  "if" "else" "switch" "case" "default"
  "while" "do" "for" "break" "continue"
  "return" "goto" "throw" "try" "catch" 
  "co_return" "co_yield" "co_await"
] @keyword

[
  "struct" "class" "union" "enum" "typename" "template" "namespace" "using" "typedef"
  "public" "private" "protected" "friend" "virtual" "explicit" "inline" "constexpr"
  "consteval" "constinit" "mutable" "extern" "register" "thread_local" "decltype" 
  "concept" "requires" "import" "module"
] @keyword

; Модификаторы типов (const, static, volatile)
[
  "const" "static" "volatile" "noexcept"
] @type.qualifier

; ===================================================================
; ТИПЫ ДАННЫХ И ПРОСТРАНСТВА ИМЕН
; ===================================================================
; Встроенные типы (int, char, double, void и т.д.)
(primitive_type) @type.builtin

; Кастомные типы, классы и структуры
(type_identifier) @type.identifier
(qualified_identifier name: (type_identifier) @type.identifier)

; Пространства имен (Namespace)
(namespace_identifier) @namespace
(qualified_identifier scope: (namespace_identifier) @namespace)
;!!(using_declaration "namespace" (namespace_identifier) @namespace)
(using_declaration 
  "namespace"
  [(identifier) (qualified_identifier)] @namespace)

; ===================================================================
; ФУНКЦИИ И МЕТОДЫ
; ===================================================================
; Объявление функций и методов
(function_declarator declarator: (identifier) @function)
(function_declarator declarator: (field_identifier) @function.method)

; Вызовы функций и методов
(call_expression function: (identifier) @function.call)
;!! (call_expression function: (field_expression result: (field_identifier) @function.method))
(call_expression 
  function: (field_expression field: (field_identifier) @function.method))

; Специфичные для С++ имена деструкторов и операторов
(destructor_name) @function
(operator_name) @function

; Шаблоны
(template_function name: (identifier) @function.call)
;!! (template_method name: (field_expression result: (field_identifier) @function.method))
(template_method name: (field_identifier) @function.method)

; ===================================================================
; ПЕРЕМЕННЫЕ, ПАРАМЕТРЫ И СВОЙСТВА
; ===================================================================
; Обычные переменные
;!! (variable_declarator declarator: (identifier) @variable)
; Переменные с инициализацией (например: int x = 5;)
(init_declarator declarator: (identifier) @variable)

; Переменные без инициализации (например: int x;)
(declaration declarator: (identifier) @variable)

; Поля структур/классов (например: int my_field;)
(field_declaration declarator: (field_identifier) @variable)

; Поля классов/структур (Properties)
(field_identifier) @variable

; Параметры функций (включая указатели и ссылки)
(parameter_declaration declarator: (identifier) @variable.parameter)
(parameter_declaration declarator: (reference_declarator (identifier) @variable.parameter))
(parameter_declaration declarator: (pointer_declarator (identifier) @variable.parameter))

; ===================================================================
; ЛИТЕРАЛЫ, СТРОКИ И ЧИСЛА
; ===================================================================
(string_literal) @string
(char_literal) @string
(number_literal) @number

; ===================================================================
; ПУНКТУАЦИЯ И ОПЕРАТОРЫ
; ===================================================================
[
  "=" "==" "!=" ">" "<" ">=" "<="
  "+" "-" "*" "/" "%" "++" "--"
  "&&" "||" "!" "&" "|" "^" "~" "<<" ">>"
  "+=" "-=" "*=" "/=" "%=" "<<=" ">>=" "&=" "^=" "|="
  "?" ":" "::" "." "->" ".*" "->*"
  "sizeof" "delete" "new"
] @operator

[ "(" ")" "{" "}" "[" "]" ] @punctuation.bracket
[ "," ";" ] @punctuation.delimiter

; ===================================================================
; ПРЕПРОЦЕССОР (ДИРЕКТИВЫ СБОРКИ)
; ===================================================================
; Сама директива (например, #define, #ifdef)
(preproc_directive) @preprocessor

; Специфика для #include
; Универсальная и безопасная подсветка для #include
(preproc_include 
  "#include" @keyword.directive.include
  path: [
    (string_literal) 
    (system_lib_string)
  ] @string.special.path
)
(preproc_include path: [ (string_literal) (preproc_arg) ] @string.special.path)

; Макросы и их использование
(preproc_def name: (identifier) @function.macro)
(preproc_function_def name: (identifier) @function.macro)

; ======================================
; комментарии
; ======================================
(comment) @comment
        """;
    }

    protected override bool is_container_node (string node_type) {
        return node_type in new string[] {
                   "class_specifier", "struct_specifier", "function_definition", "namespace_definition"
        };
    }

    protected override void prepare_capture_mapping () {
      base.prepare_capture_mapping ();
      // TODO: @comment to @comment.documentation post processing prepare implementation...
    }
}
