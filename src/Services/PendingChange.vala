/*
*/

public class Iide.PendingChange : GLib.Object {
    public int start_offset;    // Стартовая позиция в байтах
    public int end_offset;      // Конечная позиция в байтах
    public string text;         // Добавленный текст (для delete_range - пустой)

    // Замороженные позиции
    public int start_line;
    public int start_utf16_char;
    public int start_utf8_char;
    public int end_line;
    public int end_utf16_char;
    public int end_utf8_char;

    public PendingChange (string t, Gtk.TextIter s_iter, Gtk.TextIter? e_iter = null) {
        this.text = t;
        this.start_offset = s_iter.get_offset ();
        this.end_offset = e_iter != null? e_iter.get_offset () : this.start_offset;

        // Расчет позиций
        this.calculate_position (s_iter, out this.start_line, out this.start_utf16_char, out this.start_utf8_char);
        if (e_iter != null) {
            this.calculate_position (e_iter, out this.end_line, out this.end_utf16_char, out this.end_utf8_char);
        } else {
            this.end_line = this.start_line;
            this.end_utf16_char = this.start_utf16_char;
            this.end_utf8_char = this.start_utf8_char;
        }
    }

    private void calculate_position (Gtk.TextIter iter, out int line_number, out int utf16_char, out int utf8_char) {
        line_number = iter.get_line ();

        // Создаем итератор начала текущей строки для расчета смещения
        Gtk.TextIter line_start = iter;
        line_start.set_line_offset (0);

        // Получаем текст строки до итератора
        string line_text = line_start.get_text (iter);

        // Считаем UTF-16 code units
        int utf16_count = 0;
        int utf8_count = 0;
        int i = 0;
        unichar c;
        while (line_text.get_next_char (ref i, out c)) {
            utf8_count++;
            if (c <= 0xFFFF) {
                utf16_count++;
            } else {
                utf16_count += 2;
            }
        }
        utf16_char = utf16_count;
        utf8_char = utf8_count;
    }
}
