using GLib;

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

    public void copy_resource_to_file(string resource_path, string local_path) {
        // 1. Создаем объект File для ресурса (путь должен начинаться с resource:///)
        var resource_file = File.new_for_uri (resource_path);

        // 2. Создаем объект File для локального файла на диске
        var local_file = File.new_for_path (local_path);

        try {
            // 3. Выполняем копирование. Флаг OVERWRITE перезапишет файл, если он существует.
            resource_file.copy (local_file, FileCopyFlags.OVERWRITE, null, null);
            print ("Файл успешно скопирован в: %s\n", local_path);
        } catch (Error e) {
            stderr.printf ("Ошибка при копировании: %s\n", e.message);
        }
    }
}
