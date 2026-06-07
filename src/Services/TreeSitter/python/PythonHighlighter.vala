[CCode (cname = "tree_sitter_python")]
extern unowned TreeSitter.Language ? get_lang_python ();

public class Iide.PythonHighlighter : SimpleTreeSitterHighlighter {
  private int variable_idx = -1;
  private int parameter_idx = -1;
  private int type_idx = -1;

  private Gtk.TextTag?[] builtin_var_tags;
  private Gtk.TextTag?[] type_builtin_tags;
  private Gtk.TextTag?[] function_builtin_tags;

  public PythonHighlighter (SourceView view) {
    base (view);
  }

  protected override void prepare_capture_mapping () {
    base.prepare_capture_mapping();

    if (query == null)
      return;

    var style_service = StyleService.get_instance ();
    this.builtin_var_tags = {
      style_service.get_tag ("variable.builtin", 0),
      style_service.get_tag ("variable.builtin", 1),
    };
    this.type_builtin_tags = {
      style_service.get_tag ("type.builtin", 0),
      style_service.get_tag ("type.builtin", 1),
    };
    this.function_builtin_tags = {
      style_service.get_tag ("function.builtin", 0),
      style_service.get_tag ("function.builtin", 1),
    };

    uint32 count = query.capture_count ();

    for (uint32 i = 0; i < count; i++) {
      uint32 name_len;
      string name = query.capture_name_for_id (i, out name_len);

      switch (name) {
        case "ident":
          this.variable_idx = (int) i;
          break;
        case "variable.parameter":
          this.parameter_idx = (int) i;
          break;
        case "type.identifier":
          this.type_idx = (int) i;
          break;
      }
    }
  }

  private string capture_text(TreeSitter.QueryCapture capture) {
    Gtk.TextIter start_iter, end_iter;
    var buf = this.buffer; // Ваш Gtk.TextBuffer

    // Получаем итераторы напрямую по номеру строки и БАЙТОВОМУ индексу (column) внутри этой строки.
    // Метод get_iter_at_line_index() аппаратно учитывает кириллицу и любые мультибайтовые символы UTF-8.
    buf.get_iter_at_line_index (out start_iter, (int) capture.node.start_point ().row, (int) capture.node.start_point ().column);
    buf.get_iter_at_line_index (out end_iter, (int) capture.node.end_point ().row, (int) capture.node.end_point ().column);

    // Возвращаем чистый текст, который теперь будет извлечен без единого сдвига
    return buf.get_text (start_iter, end_iter, true);
  }
  
  protected override Gtk.TextTag? capture_tag(TreeSitter.QueryCapture capture, int theme_index) {
    int current_idx = (int) capture.index;

    if (current_idx == type_idx) {
      switch (capture_text(capture)) {
        case "bool": case "bytearray": case "bytes":
        case "complex": case "dict": case "float":
        case "frozenset": case "int": case "list":
        case "map": case "memoryview": case "object":
        case "set": case "str": case "tuple": case "type":
          return this.type_builtin_tags[theme_index];
      }
    }

    else if (current_idx == variable_idx || current_idx == parameter_idx) {
      switch (capture_text(capture)) {
        case "self": case "cls":
          return this.builtin_var_tags[theme_index];

        case "bool": case "bytearray": case "bytes":
        case "classmethod": case "complex": case "dict":
        case "enumerate": case "filter": case "float":
        case "frozenset": case "int": case "list":
        case "map": case "memoryview": case "object":
        case "property": case "range": case "set":
        case "slice": case "staticmethod": case "str":
        case "super": case "tuple": case "type":
          return this.type_builtin_tags[theme_index];

        case "abs": case "all": case "any": case "ascii":
        case "bin": case "breakpoint": case "callable": case "chr":
        case "compile": case "delattr": case "dir": case "divmod":
        case "eval": case "exec": case "format": case "getattr":
        case "globals": case "hasattr": case "hash": case "help":
        case "hex": case "id": case "input": case "isinstance":
        case "issubclass": case "iter": case "len": case "locals":
        case "max": case "min": case "next": case "oct": case "open":
        case "ord": case "pow": case "print": case "repr":
        case "reversed": case "round": case "setattr": case "sorted":
        case "sum": case "vars": case "zip": case "__import__":
          return this.function_builtin_tags[theme_index];
      }
    }

    return base.capture_tag (capture, theme_index);
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

      ; ===================================================================
      ; ФУНКЦИИ, МЕТОДЫ И КЛАССЫ
      ; ===================================================================
      ; Объявление классов и типов
      (class_definition name: (identifier) @type)
      ; Объявление функций и методов
      (function_definition name: (identifier) @function)

      ; Родительские типы классов
      (class_definition superclasses: (argument_list (identifier) @type.identifier))

      ; Встроенные переменные self, cls
      (class_definition body: (block (function_definition
        (parameters . (typed_parameter (identifier) @variable.builtin)))))
      (class_definition body: (block (function_definition
        (parameters . (identifier) @variable.builtin))))
            
      ; Ппараметры функций 
      (parameters (identifier) @variable.parameter)
      (parameters (typed_parameter (identifier) @variable.parameter))
      (parameters (default_parameter name: (identifier) @variable.parameter))
      (parameters (typed_default_parameter name: (identifier) @variable.parameter))

      ; Именованные аргументы функций
      (keyword_argument name: (identifier) @variable.parameter)

      ; Хинты типов
      (type (identifier) @type.identifier)
      (type (binary_operator (identifier) @type.identifier))

      ; Вызовы функций и методов
      (call function: (identifier) @function.call)
      (call function: (attribute attribute: (identifier) @function.method))

      ; Декораторы (@classmethod, @staticmethod)
      (decorator) @attribute
      (decorator (identifier) @attribute)
      (decorator (call function: (identifier) @attribute))
      
      ; Базовый идентификатор
      (identifier) @ident
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