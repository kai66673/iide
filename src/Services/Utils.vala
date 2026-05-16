using GLib;

[CCode(cheader_filename = "unistd.h")]
extern int getpid();

namespace Iide {
    public string mime_type_for_file(File file) {
        string mime_type = "text-x";
        try {
            var info = file.query_info("standard::*", FileQueryInfoFlags.NONE, null);
            mime_type = ContentType.get_mime_type(info.get_attribute_as_string(FileAttribute.STANDARD_CONTENT_TYPE));
        } catch (Error e) {
        }
        return mime_type;
    }

    public int application_pid() {
        return getpid();
    }

    public void copy_resource_to_file(string resource_path, string local_path) {
        // 1. Создаем объект File для ресурса (путь должен начинаться с resource:///)
        var resource_file = File.new_for_uri(resource_path);

        // 2. Создаем объект File для локального файла на диске
        var local_file = File.new_for_path(local_path);

        try {
            // 3. Выполняем копирование. Флаг OVERWRITE перезапишет файл, если он существует.
            resource_file.copy(local_file, FileCopyFlags.OVERWRITE, null, null);
            print("Файл успешно скопирован в: %s\n", local_path);
        } catch (Error e) {
            stderr.printf("Ошибка при копировании: %s\n", e.message);
        }
    }

    public string ? escape_pango(string? text) {
        if (text == null)
            return null;
        return text
                .replace("&", "&amp;")
                .replace("<", "&lt;")
                .replace(">", "&gt;");
    }

    private uint32 get_byte_offset_safe (Gtk.TextIter iter) {
        int target_line = iter.get_line ();
        int current_line_bytes = iter.get_line_index (); // Байты от начала текущей строки (O(1))

        // Если мы на первой строке, оффсет равен индексу внутри строки
        if (target_line == 0) {
            return (uint32) current_line_bytes;
        }

        uint32 total_bytes = 0;
        Gtk.TextIter line_runner;
        iter.get_buffer ().get_start_iter (out line_runner);

        // Быстро прыгаем по строкам вперед до нашей целевой строки.
        // Метод get_bytes_in_line() у TextIter выполняется мгновенно внутри B-дерева GTK, 
        // возвращая длину строки в байтах (включая \n) БЕЗ выделения памяти и копирования текста!
        for (int i = 0; i < target_line; i++) {
            total_bytes += (uint32) line_runner.get_bytes_in_line ();
            if (!line_runner.forward_line ()) break;
        }

        // Прибавляем байты внутри целевой строки
        total_bytes += (uint32) current_line_bytes;

        return total_bytes;
    }
}