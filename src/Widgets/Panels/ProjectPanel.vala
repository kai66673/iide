public class Iide.ProjectPanel : BasePanel {
    public FileTreeView folder_view;

    public ProjectPanel () {
        base ("Project Tree", "folder-symbolic");
        folder_view = new FileTreeView ();
        child = folder_view;
        can_maximize = true;

        // Подключаем сигналы менеджера проекта
        var project_manager = ProjectManager.get_instance ();
        project_manager.project_opened.connect ((project_root) => {
            folder_view.set_root_file (project_root);
        });

        project_manager.project_closed.connect (() => {
            folder_view.set_root_file (null);
        });

        // Handle file activation to open documents
        var document_manager = DocumentManager.get_instance ();
        folder_view.file_activated.connect ((item) => {
            if (!item.is_directory) {
                document_manager.open_document (item.file, null);
            }
        });
    }

    public override Panel.Position initial_pos () {
        return new Panel.Position () { area = Panel.Area.START };
    }

    public override string panel_id () {
        return "ProjectPanel";
    }
}
