/*
*/

public class Iide.ProjectPanel : BasePanel {
    public FileTreeView folder_view;

    public ProjectPanel (WindowSession session) {
        base (session, "Project Tree", ImageFactory.icon_name_for_id (IconID.APP_PROJECT));
        folder_view = new FileTreeView ();
        child = folder_view;
        can_maximize = true;

        // Подключаем сигналы менеджера проекта
        var project_manager = this.session.project_manager;
        project_manager.project_opened.connect ((project_root) => {
            folder_view.set_root_file (project_root);
        });

        project_manager.project_closed.connect (() => {
            folder_view.set_root_file (null);
        });

        folder_view.file_activated.connect ((item) => {
            if (!item.is_directory) {
                this.session.document_manager.open_document (item.file, null);
            }
        });

        folder_view.file_rename_requested.connect ((item) => {
            if (item.is_directory)
                return;

            var dialog = new RenameFileDialog (this.session.window, item.file);
            dialog.confirmed.connect ((new_name) => {
                var new_file = item.file.get_parent ().get_child (new_name);
                this.session.file_operations_service.rename_file_async.begin (item.file, new_file, (obj, res) => {
                    bool renamed = this.session.file_operations_service.rename_file_async.end (res);
                    if (renamed) {
                        this.folder_view.refresh ();
                    }
                });
            });
            dialog.present ();
        });

        folder_view.create_entry_requested.connect ((item, is_directory) => {
            // Новый элемент создаётся внутри папки под курсором,
            // либо в родительской папке, если под курсором файл
            var parent_dir = item.is_directory ? item.file : item.file.get_parent ();
            if (parent_dir == null)
                return;

            var dialog = new CreateFileDialog (this.session.window, parent_dir, is_directory);
            dialog.confirmed.connect ((name) => {
                this.session.file_operations_service.create_entry_async.begin (parent_dir, name, is_directory, (obj, res) => {
                    bool created = this.session.file_operations_service.create_entry_async.end (res);
                    if (created) {
                        this.folder_view.refresh ();

                        var new_file = parent_dir.get_child (name);

                        // Раскрываем дерево до созданного элемента и выделяем его
                        this.folder_view.select_file (new_file);

                        // Новый файл сразу открываем в редакторе
                        if (!is_directory) {
                            this.session.document_manager.open_document (new_file, null);
                        }
                    }
                });
            });
            dialog.present ();
        });
    }

    public override Panel.Position initial_pos () {
        return new Panel.Position () { area = Panel.Area.START };
    }

    public override string panel_id () {
        return "ProjectPanel";
    }
}