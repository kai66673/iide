/*
*/

public class Iide.PendingChange : GLib.Object {
    public int start_offset;    // Стартовая позиция в байтах
    public int end_offset;      // Конечная позиция в байтах
    public string text;         // Добавленный текст (для delete_range - пустой)

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
