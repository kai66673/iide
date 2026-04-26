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

public enum Iide.IdeLspCompletionKind {
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

public class Iide.PendingChange : GLib.Object {
    public int start_offset;
    public int end_offset;
    public string text;

    // Замороженные координаты LSP
    public int start_line;
    public int start_char;
    public int end_line;
    public int end_char;

    public PendingChange (string t, Gtk.TextIter s_iter, Gtk.TextIter? e_iter = null) {
        this.text = t;
        this.start_offset = s_iter.get_offset ();
        this.end_offset = e_iter != null? e_iter.get_offset () : this.start_offset;

        // Расчет позиций
        this.calculate_lsp_pos (s_iter, out this.start_line, out this.start_char);
        if (e_iter != null) {
            this.calculate_lsp_pos (e_iter, out this.end_line, out this.end_char);
        } else {
            this.end_line = this.start_line;
            this.end_char = this.start_char;
        }
    }

    private void calculate_lsp_pos (Gtk.TextIter iter, out int lsp_line, out int lsp_char) {
        lsp_line = iter.get_line ();

        // Создаем итератор начала текущей строки для расчета смещения
        Gtk.TextIter line_start = iter;
        line_start.set_line_offset (0);

        // Получаем текст строки до итератора
        string line_text = line_start.get_text (iter);

        // Считаем UTF-16 code units
        int utf16_count = 0;
        int i = 0;
        unichar c;
        while (line_text.get_next_char (ref i, out c)) {
            if (c <= 0xFFFF) {
                utf16_count += 1;
            } else {
                utf16_count += 2;
            }
        }
        lsp_char = utf16_count;
    }
}

public class Iide.IdeLspCompletionItem : GLib.Object {
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
    public IdeLspCompletionKind kind { get; set; default = IdeLspCompletionKind.TEXT; }
}

public class Iide.IdeLspDiagnostic : GLib.Object {
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

public class Iide.IdeLspLocation : GLib.Object {
    public string uri { get; set; }
    public int start_line { get; set; }
    public int start_column { get; set; }
    public int end_line { get; set; }
    public int end_column { get; set; }
}

public class Iide.IdeLspCompletionResult : GLib.Object {
    public Gee.ArrayList<IdeLspCompletionItem> items { get; set; }
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

public class Iide.LspSymbol : Object {
    public string name { get; set; }
    public SymbolKind kind { get; set; }
    public string uri { get; set; }
    public int start_line { get; set; }
    public int start_char { get; set; }
    public string? container_name { get; set; }
}