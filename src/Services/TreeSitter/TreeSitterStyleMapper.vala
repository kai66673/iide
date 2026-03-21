using Gtk;
using GtkSource;

public class Iide.TreeSitterStyleMapper : Object {
    private Gee.HashMap<string, string> map;
    private StyleScheme scheme;
    private TextBuffer buffer;

    public TreeSitterStyleMapper(TextBuffer buffer) {
        this.buffer = buffer;
        this.scheme = ((Buffer)buffer).style_scheme;
        this.map = new Gee.HashMap<string, string>();

        // Заполняем таблицу соответствий (Tree-sitter -> GtkSourceView)
        map["keyword"] = "def:keyword";
        map["function"] = "def:function";
        map["function.method"] = "def:function";
        map["variable.builtin"] = "def:special-constant";
        map["string"] = "def:string";
        map["comment"] = "def:comment";
        map["type"] = "def:type";
        map["constant"] = "def:constant";
        map["operator"] = "def:operator";
        map["punctuation.bracket"] = "def:operator"; // или кастомный
    }

    public void apply_highlight(string ts_capture_name, TextIter start, TextIter end) {
        // 1. Ищем, на какой стандартный стиль ссылается токен Tree-sitter
        string? style_id = map[ts_capture_name];
        if (style_id == null) return;

        // 2. Генерируем уникальное имя для тега в таблице (например, "ts:def:keyword")
        string tag_name = "ts:" + style_id;
        var tag = buffer.tag_table.lookup(tag_name);

        if (tag == null) {
            // 3. Если тега еще нет, создаем его на основе GtkSourceStyle
            var style = scheme.get_style(style_id);
            if (style != null) {
                tag = new TextTag(tag_name);
                copy_style_to_tag(style, tag);
                buffer.tag_table.add(tag);
            }
        }

        // 4. Применяем тег к тексту
        if (tag != null) {
            buffer.apply_tag(tag, start, end);
        }
    }

    private void copy_style_to_tag(GtkSource.Style style, TextTag tag) {
        if (style.foreground_set) tag.foreground = style.foreground;
        if (style.background_set) tag.background = style.background;
        if (style.bold_set) tag.weight = style.bold ? Pango.Weight.BOLD : Pango.Weight.NORMAL;
        if (style.italic_set) tag.style = style.italic ? Pango.Style.ITALIC : Pango.Style.NORMAL;
    }
}
