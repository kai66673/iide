/*
*/

using GLib;
using Gtk;

public class Iide.FormattingService : GLib.Object {
    private static FormattingService? instance = null;

    public static FormattingService get_instance () {
        if (instance == null) {
            instance = new FormattingService ();
        }
        return instance;
    }

    private FormattingService () {
        Object ();
    }

    // Основной асинхронный метод форматирования
    public async bool format_document_async (SourceView source_view) {
        var buffer = source_view.buffer;
        var doc = source_view.document as TreeSitterDocument;
        if (doc == null)
            return false;

        // Корректно получаем File для определения языка
        var file = File.new_for_uri (source_view.uri);
        var lsp_service = LspService.get_instance ();
        string lang_id = lsp_service.get_language_id_for_file (file);

        LoggerService.get_instance ().info (
            "Formatter", "Request formatting for language: %s (File: %s)"
            .printf (lang_id, source_view.uri)
        );

        if (lang_id == "python") {
            // Получаем базовое имя файла (например, main.py). 
            // Это необходимо для ruff, чтобы он знал, какие правила применять
            string filename = file.get_basename () ?? "main.py";
            
            // ФОРМИРУЕМ ЦЕПОЧКУ КОМАНД: Сначала линтинг с авто-исправлением, затем форматирование.
            // Одинарные кавычки вокруг '%s' защищают от пробелов в путях/именах файлов.
            string shell_pipeline = "ruff check - --fix -q --stdin-filename '%s' | ruff format - --stdin-filename '%s'"
                .printf (filename, filename);

            return yield this.format_with_pipeline_async (doc, buffer, shell_pipeline);
        } else {
            // Для всех остальных языков пытаемся использовать LSP
            return yield this.format_with_lsp_async (source_view, doc);
        }
    }

    // Новая стратегия А: Выполнение цепочки команд (пайплайна) через системный Shell
    private async bool format_with_pipeline_async (TreeSitterDocument doc, Gtk.TextBuffer buffer, string pipeline_command) {
        try {
            // Получаем весь текущий текст из буфера
            Gtk.TextIter start, end;
            buffer.get_bounds (out start, out end);
            string input_text = buffer.get_text (start, end, true);

            // Настраиваем запуск процесса с перенаправлением всех потоков
            var launcher = new SubprocessLauncher (SubprocessFlags.STDIN_PIPE | SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_PIPE);
            
            // Запускаем командный интерпретатор sh и передаем ему всю строку пайплайна
            string[] full_args = { "/bin/sh", "-c", pipeline_command };
            var process = launcher.spawnv (full_args);

            // Переменные, куда GLib запишет ответы из потоков
            string formatted_code;
            string err_output;

            // ===================================================================
            // ИСПРАВЛЕНИЕ: Используем communicate_utf8_async. 
            // Он сам атомарно запишет input_text в stdin, закроет его,
            // асинхронно дождется завершения процесса и вернет stdout и stderr.
            // ===================================================================
            yield process.communicate_utf8_async (input_text, null, out formatted_code, out err_output);

            // Проверяем, были ли сообщения в потоке ошибок
            if (err_output != null && err_output.length > 0) {
                LoggerService.get_instance ().warning ("Formatter", "Pipeline stderr output: %s".printf (err_output));
            }

            // Проверяем код завершения процесса shell
            yield process.wait_check_async (null);

            // ===================================================================
            // ИСПРАВЛЕНИЕ: Выносим изменение текста буфера из асинхронного контекста
            // в безопасный цикл ожидания (Idle.add).
            // ===================================================================
            if (formatted_code != null && formatted_code.length > 0 && formatted_code != input_text) {
                
                Timeout.add (50, () => {
                    buffer.begin_user_action ();
                    buffer.set_text (formatted_code, -1);
                    buffer.end_user_action ();
                    
                    // Форсируем полный репарсинг Tree-Sitter
                    doc.ts_highlighter.force_full_reparse (); 

                    
                    LoggerService.get_instance ().info ("Formatter", "Successfully formatted with delayed user action.");
                    return Source.REMOVE; 
                });

                return true;
            }

        } catch (GLib.Error e) {
            LoggerService.get_instance ().error ("Formatter", "Failed to run pipeline: %s".printf (e.message));
        }
        return false;
    }
    // Стратегия Б: Форматирование через встроенный LSP-клиент
    private async bool format_with_lsp_async (Gtk.TextView text_view, Iide.TreeSitterDocument doc) {
        LoggerService.get_instance ().debug ("Formatter", "LSP Formatting Strategy is not linked yet.");
        return false;
    }
}
