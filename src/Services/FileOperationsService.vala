/*
 * FileOperationsService.vala
 *
 * Сервис операций над файлами (сейчас — переименование) с полной
 * интеграцией с LSP: workspace/willRenameFiles -> правки -> фактический
 * перенос -> workspace/didRenameFiles + пересборка состояния проекта.
 */

public class Iide.FileOperationsService : GLib.Object {
    public weak WindowSession session;
    private LoggerService logger;

    public signal void file_renamed (string old_uri, string new_uri);
    public signal void file_created (string uri, bool is_directory);

    public FileOperationsService (WindowSession session) {
        this.session = session;
        this.logger = session.logger_service;
    }

    /**
     * Полный цикл переименования файла:
     *  1) проверка несохранённых изменений (диалог Save / Rename without saving / Cancel);
     *  2) workspace/willRenameFiles (правки импортов/ссылок от серверов);
     *  3) закрытие вкладки (textDocument/didClose);
     *  4) физический перенос файла на диске;
     *  5) переоткрытие под новым именем (didOpen);
     *  6) применение правок серверов;
     *  7) workspace/didRenameFiles;
     *  8) пересборка состояния, привязанного к URI (закладки, история, кэши).
     *
     * @return true если файл переименован, false если операция отменена или провалилась.
     */
    public async bool rename_file_async (GLib.File old_file, GLib.File new_file) {
        string old_uri = old_file.get_uri ();
        string new_uri = new_file.get_uri ();

        if (old_uri == new_uri)
            return false;

        if (new_file.query_exists (null)) {
            this.logger.error ("FS-OP", "Cannot rename: target already exists: %s".printf (new_file.get_path ()));
            return false;
        }

        // 1. Несохранённые изменения — спрашиваем пользователя
        var text_view = this.session.document_manager.documents.get (old_uri) as Iide.TextView;
        if (text_view != null && text_view.is_modified) {
            bool proceed = yield this.confirm_unsaved_changes_async (old_uri);
            if (!proceed)
                return false;
        }

        // 2. Проталкиваем неотправленные правки ввода из ВСЕХ открытых вкладок,
        //    чтобы серверы строили правки willRenameFiles по актуальному тексту.
        //    Если какой-то открытый файл остался рассинхронизирован (400 мс дебаунс),
        //    сервер вернёт диапазоны правок по устаревшему дереву — они не совпадут
        //    с буфером и рассинхронизируют файлы с сопутствующими правками.
        foreach (var doc in this.session.document_manager.documents.values) {
            yield doc.source_view.lsp_sync_changes_async ();
        }

        // 3. Спрашиваем серверы о правках до переименования (импорты/ссылки)
        var edits = yield this.session.lsp_service.will_rename_files_async (old_uri, new_uri);

        // 4. Закрываем вкладку (отправляет textDocument/didClose серверам)
        this.session.document_manager.close_document (old_uri);

        // 5. Физическое перемещение файла
        try {
            old_file.move (new_file, GLib.FileCopyFlags.NONE, null, null);
        } catch (GLib.Error e) {
            this.logger.error ("FS-OP", "Rename failed: %s".printf (e.message));
            return false;
        }

        // 6. Переоткрываем файл под новым именем (сервер получит didOpen)
        this.session.document_manager.open_document_by_uri (new_uri);

        // 7. Применяем правки серверов. Правки по старому URI пропускаем —
        //    файла с таким именем больше не существует.
        if (edits != null) {
            foreach (var entry in edits.entries) {
                if (entry.key == old_uri)
                    continue;
                this.session.document_manager.apply_edits_to_file (entry.key, entry.value);
            }
        }

        // 8. Сообщаем серверам о завершённом переименовании
        yield this.session.lsp_service.notify_did_rename_files (old_uri, new_uri);

        // 9. Пересобираем состояние, привязанное к URI файла
        foreach (var mark_service in this.session.marks_service) {
            mark_service.move_marks_uri (old_uri, new_uri);
        }
        this.session.navigation_history_service.rewrite_file_uri (old_uri, new_uri);
        this.session.project_manager.invalidate_file_cache ();

        this.file_renamed (old_uri, new_uri);
        this.logger.info ("FS-OP", "Renamed %s -> %s".printf (old_file.get_path (), new_file.get_path ()));
        return true;
    }

    /**
     * Создаёт новый файл или директорию в указанной родительской папке.
     *
     * @param parent_dir родительская директория, в которой создаётся элемент
     * @param name        имя (basename) нового файла/директории
     * @param is_directory true — создать директорию, false — пустой файл
     * @return true если элемент создан, false если имя невалидно,
     *         элемент уже существует или произошла ошибка.
     */
    public async bool create_entry_async (GLib.File parent_dir, string name, bool is_directory) {
        string cleaned = name.strip ();
        if (cleaned.length == 0 || cleaned == "." || cleaned == ".."
                || cleaned.contains ("/")) {
            this.logger.error ("FS-OP", "Cannot create '%s': invalid name".printf (name));
            return false;
        }

        var target = parent_dir.get_child (cleaned);
        if (target.query_exists (null)) {
            this.logger.error ("FS-OP", "Cannot create '%s': already exists".printf (target.get_path ()));
            return false;
        }

        try {
            if (is_directory) {
                target.make_directory (null);
            } else {
                var stream = target.create (GLib.FileCreateFlags.NONE, null);
                stream.close (null);
            }
        } catch (GLib.Error e) {
            this.logger.error ("FS-OP", "Create %s failed: %s".printf (is_directory ? "directory" : "file", e.message));
            return false;
        }

        this.file_created (target.get_uri (), is_directory);
        this.logger.info ("FS-OP", "Created %s %s".printf (is_directory ? "directory" : "file", target.get_path ()));
        return true;
    }

    /**
     * Диалог про несохранённые изменения: Save / Rename without saving / Cancel.
     */
    private async bool confirm_unsaved_changes_async (string uri) {
        var dialog = new Adw.AlertDialog (
            _("Unsaved Changes"),
            _("The file has unsaved changes. Save it before renaming?")
        );

        dialog.add_response ("cancel", _("Cancel"));
        dialog.add_response ("discard", _("Rename without saving"));
        dialog.add_response ("save", _("Save"));
        dialog.set_response_appearance ("save", Adw.ResponseAppearance.SUGGESTED);
        dialog.set_close_response ("cancel"); // Esc сработает как Cancel

        SourceFunc resume_callback = confirm_unsaved_changes_async.callback;
        string chosen = "cancel";
        dialog.response.connect ((response) => {
            chosen = response;
            Idle.add_full (Priority.HIGH, (owned) resume_callback);
        });

        dialog.present (this.session.window);
        yield;

        switch (chosen) {
            case "save":
                var tv = this.session.document_manager.documents.get (uri) as Iide.TextView;
                if (tv != null)
                    tv.save ();
                return true;
            case "discard":
                return true;
            case "cancel":
            default:
                return false;
        }
    }
}
