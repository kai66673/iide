public enum Iide.CompletionTriggerKind {
    /**
     * Дополнение вызвано вручную (например, Ctrl+Space)
     * или обычным набором текста, не являющегося триггером.
     */
    INVOKED = 1,

    /**
     * Дополнение вызвано вводом специфического символа-триггера
     * (например, '.', ':', '->').
     */
    TRIGGER_CHARACTER = 2,

    /**
     * Дополнение вызвано повторным запросом (например, когда
     * список был помечен как 'incomplete').
     */
    TRIGGER_FOR_INCOMPLETE_COMPLETIONS = 3
}

public enum Iide.LspCompletionKind {
    TEXT = 1,
    METHOD = 2,
    FUNCTION = 3,
    CONSTRUCTOR = 4,
    FIELD = 5,
    VARIABLE = 6,
    CLASS = 7,
    INTERFACE = 8,
    MODULE = 9,
    PROPERTY = 10,
    UNIT = 11,
    VALUE = 12,
    ENUM = 13,
    KEYWORD = 14,
    SNIPPET = 15,
    COLOR = 16,
    FILE = 17,
    REFERENCE = 18,
    FOLDER = 19,
    ENUM_MEMBER = 20,
    CONSTANT = 21,
    STRUCT = 22,
    EVENT = 23,
    OPERATOR = 24,
    TYPE_PARAMETER = 25;
}

public class Iide.LspCompletionItem : GLib.Object {
    public string label { get; set; default = ""; }
    public string? detail { get; set; }
    public string? documentation { get; set; }
    public int sort_text_priority { get; set; default = 0; }
    public int insert_text_priority { get; set; default = 0; }
    public string insert_text { get; set; default = ""; }
    public string? text_edit { get; set; }
    public int start_line { get; set; default = 0; }
    public int start_column { get; set; default = 0; }
    public int end_line { get; set; default = 0; }
    public int end_column { get; set; default = 0; }
    public LspCompletionKind kind { get; set; default = LspCompletionKind.TEXT; }
}

public class Iide.LspDiagnostic : GLib.Object {
    public int severity { get; set; default = 1; }
    public string message { get; set; default = ""; }
    public int start_line { get; set; default = 0; }
    public int start_column { get; set; default = 0; }
    public int end_line { get; set; default = 0; }
    public int end_column { get; set; default = 0; }

    public string to_string () {
        return "Diagnostic: (%d:%d-%d:%d) %s".printf (start_line, start_column, end_line, end_column, message);
    }
}

public class Iide.LspLocation : GLib.Object {
    public string uri { get; set; }
    public int start_line { get; set; }
    public int start_column { get; set; }
    public int end_line { get; set; }
    public int end_column { get; set; }
}

public class Iide.LspCompletionResult : GLib.Object {
    public Gee.ArrayList<LspCompletionItem> items { get; set; }
    public bool is_incomplete { get; set; default = false; }
}

public enum Iide.SymbolKind {
    FILE = 1, MODULE = 2, NAMESPACE = 3, PACKAGE = 4,
    CLASS = 5, METHOD = 6, PROPERTY = 7, FIELD = 8,
    CONSTRUCTOR = 9, ENUM = 10, INTERFACE = 11,
    FUNCTION = 12, VARIABLE = 13, CONSTANT = 14,
    STRING = 15, NUMBER = 16, BOOLEAN = 17,
    ARRAY = 18, OBJECT = 19, KEY = 20, NULL = 21,
    ENUM_MEMBER = 22, STRUCT = 23, EVENT = 24,
    OPERATOR = 25, TYPE_PARAMETER = 26;
}

public class Iide.WorkspaceLspSymbol : Object {
    public string name { get; set; }
    public SymbolKind kind { get; set; }
    public string uri { get; set; }
    public int start_line { get; set; }
    public int start_char { get; set; }
    public string? container_name { get; set; }
}

public class Iide.DocumentLspSymbol : Object {
    public string name { get; set; }
    public SymbolKind kind { get; set; }
    public int start_line { get; set; }
    public int start_char { get; set; }
    public string? container_name { get; set; }
    public Gee.List<DocumentLspSymbol> children { get; set; default = new Gee.ArrayList<DocumentLspSymbol> (); }
}