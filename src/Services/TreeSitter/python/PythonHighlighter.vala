[CCode (cname = "tree_sitter_python")]
extern unowned TreeSitter.Language ? get_lang_python ();

public class Iide.PythonHighlighter : BaseTreeSitterHighlighter {
  public PythonHighlighter (SourceView view) {
    base (view);
  }

  protected override unowned TreeSitter.Language get_ts_language () {
    return get_lang_python ();
  }

  protected override string query_source () {
    return """
      ; ===================================================================
      ; ПОДСВЕТКА ИМПОРТОВ (МОДУЛИ И ПАКЕТЫ)
      ; ===================================================================

      ; 1. Конструкция: import os, sys
      ; Выделяем ключевое слово и имена подключаемых модулей
      (import_statement "import" @keyword.control.import)
      (import_statement (dotted_name) @namespace)

      ; 2. Конструкция: from os import path
      ; Выделяем ключевые слова и корневой модуль/пакет
      (import_from_statement "from" @keyword.control.import)
      (import_from_statement "import" @keyword.control.import)
      (import_from_statement module_name: (dotted_name) @namespace)

      ; 3. Выделение конкретных объектов, импортируемых из модуля (from math import sin, cos)
      ; Их часто красят либо как namespace, либо как обычные переменные/функции. 
      ; Самый чистый вариант — покрасить их как namespace, так как это ссылки на объекты модуля.
      (import_from_statement name: (dotted_name) @namespace)
      (aliased_import name: (dotted_name) @namespace)

      ; 4. Обработка псевдонимов (import numpy as np)
      ; Подсвечиваем ключевое слово "as" специальным импортным тегом
      (aliased_import "as" @keyword.control.import)
      ; Сам псевдоним (np) красим как namespace
      (aliased_import alias: (identifier) @namespace)

      ; 5. Импорт всего содержимого (from math import *)
      (wildcard_import "*" @operator)
      ; ===================================================================
      ; ИДЕНТИФИКАТОРЫ И ПЕРЕМЕННЫЕ
      ; ===================================================================
      ; Базовое правило для всех переменных
      (identifier) @variable

      ; Параметры в объявлении функций (def foo(param1, param2):)
      (parameters (identifier) @variable.parameter)
      (parameters (typed_parameter (identifier) @variable.parameter))
      (parameters (default_parameter name: (identifier) @variable.parameter))
      (keyword_argument name: (identifier) @variable.parameter)

      ; Именованные аргументы при вызове функций (foo(arg1=val))
      (keyword_argument name: (identifier) @variable.parameter)

      ; Свойства и атрибуты объектов (self.my_property)
      (attribute attribute: (identifier) @property)

      ; ===================================================================
      ; ФУНКЦИИ, МЕТОДЫ И КЛАССЫ
      ; ===================================================================
      ; Объявление классов и типов
      (class_definition name: (identifier) @type)

      ; Объявление функций и методов
      (function_definition name: (identifier) @function)

      ; Вызовы функций и методов
      (call function: (identifier) @function.call)
      (call function: (attribute attribute: (identifier) @function.method))

      ; Декораторы (@classmethod, @staticmethod)
      (decorator) @attribute
      (decorator (identifier) @attribute)
      (decorator (call function: (identifier) @attribute))

      ; ===================================================================
      ; ЛИТЕРАЛЫ, СТРОКИ И ЧИСЛА
      ; ===================================================================
      ; Встроенные константы
      [
        (none)
        (true)
        (false)
      ] @boolean

      [
        (integer)
        (float)
      ] @number

      (comment) @comment
      (string) @string
      (escape_sequence) @escape

      ; F-строки (Интерполяция)
      (interpolation
        "{" @punctuation.bracket
        "}" @punctuation.bracket) @none

      ; ===================================================================
      ; ОПЕРАТОРЫ И ПУНКТУАЦИЯ
      ; ===================================================================
      [
        "-" "-=" "!=" "*" "**" "**=" "*=" "/" "//" "//=" "/="
        "&" "&=" "%" "%=" "^" "^=" "+" "->" "+=" "<" "<<" "<<="
        "<=" "<>" "=" ":=" "==" ">" ">=" ">>" ">>=" "|" "|=" "~" "@="
        "and" "in" "is" "not" "or" "is not" "not in"
      ] @operator

      ["(" ")" "[" "]" "{" "}"] @punctuation.bracket
      ["." "," ":" ";" "@"] @punctuation.delimiter

      ; ===================================================================
      ; КЛЮЧЕВЫЕ СЛОВА
      ; ===================================================================
      [
        "as" "assert" "async" "await" "break" "class" "continue" "def"
        "del" "elif" "else" "except" "exec" "finally" "for" "from"
        "global" "if" "import" "lambda" "nonlocal" "pass" "print"
        "raise" "return" "try" "while" "with" "yield" "match" "case"
      ] @keyword
    """;
  }

  protected override bool is_container_node (string node_type) {
    return node_type in new string[] {
             "function_definition", "class_definition", "module_definition"
    };
  }

  protected override bool is_foldable_node_type (string type) {
    // Специфика AST Python
    return type == "function_definition" || 
           type == "class_definition" || 
           type == "if_statement" || 
           type == "for_statement" || 
           type == "while_statement" || 
           type == "try_statement" ||
           type == "with_statement" ||
           type == "match_statement" ||
           type == "case_clause";
  }

  protected override TreeSitter.Point body_start_point(TreeSitter.Node foldable_node) {
    for (uint32 j = 0; j < foldable_node.child_count (); j++) {
      var inner_child = foldable_node.child (j);
      if (inner_child.type () == ":")
        return inner_child.start_point ();
    }
    return foldable_node.start_point ();
  }

  public override GtkSource.Indenter? create_indenter() {
    return new PythonIndenter(this, get_ts_language ());
  }
}