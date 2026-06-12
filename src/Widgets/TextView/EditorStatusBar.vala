public class Iide.EditorStatusBar : Gtk.Box {
    private SourceView source_view;
    private Gtk.Label pos_label;
    private Gtk.Label mode_label;

    private DiagnosticsBar diagnostic_bar;
    
    private Gtk.Stack left_stack;
    private BreadcrumbsBar breadcrumps_bar;
    private FindBar find_bar;


    public EditorStatusBar (SourceView source_view) {
        Object (orientation: Gtk.Orientation.HORIZONTAL, spacing: 12);
        this.source_view = source_view;
        this.add_css_class ("editor-status-bar");

        // Левая часть: Breadcrumbs | FindBar
        this.breadcrumps_bar = new BreadcrumbsBar (source_view);
        this.breadcrumps_bar.update_file_path (GLib.File.new_for_uri (source_view.uri),
                                          GLib.File.new_for_path (ProjectManager.get_instance ().get_workspace_root_path ()));

        this.find_bar = new FindBar (source_view);

        this.left_stack = new Gtk.Stack ();
        // Настраиваем красивую плавную анимацию скольжения (Slide) при переключении
        this.left_stack.transition_type = Gtk.StackTransitionType.SLIDE_LEFT_RIGHT;
        this.left_stack.transition_duration = 200; // 200 миллисекунд
        this.left_stack.add_named (this.breadcrumps_bar, "breadcrumbs");
        this.left_stack.add_named (this.find_bar, "find");
        this.append (this.left_stack);

        // При запросе Esc из панели поиска возвращаем хлебные крошки
        this.find_bar.close_requested.connect (() => {
            this.hide_search_bar ();
        });

        // spacer
        var spacer_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 2);
        spacer_box.hexpand = true;
        this.append (spacer_box);

        // Правая часть: Статистика
        var info_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);

        mode_label = new Gtk.Label ("INS");
        mode_label.add_css_class ("dim-label");
        mode_label.height_request = 24;

        pos_label = new Gtk.Label ("1:1");

        info_box.append (mode_label);
        info_box.append (pos_label);
        this.append (info_box);

        diagnostic_bar = new DiagnosticsBar (source_view);

        // Добавляем в инфо-бокс перед позицией курсора
        info_box.prepend (diagnostic_bar);
    }

    /**
     * Проверить, отображается ли сейчас панель поиска на экране
     */
    public bool is_search_bar_visible () {
        return this.left_stack.get_visible_child_name () == "find";
    }

    /**
     * МЕТОДЫ ОТОБРАЖЕНИЯ ПАНЕЛЕЙ
     */
    public void show_search_bar () {
        string? selected_text = null;
        Gtk.TextIter start, end;
        var buffer = this.source_view.get_buffer ();

        // Считываем выделение СТРОГО ДО переключения стека и ухода фокуса в инпут
        if (buffer.get_selection_bounds (out start, out end)) {
            selected_text = buffer.get_text (start, end, true);
        }

        // Переключаем стек
        this.left_stack.set_visible_child_name ("find");
        
        // Передаем прочитанное выделение в панель поиска
        this.find_bar.grab_search_focus (selected_text);
    }

    public void hide_search_bar () {
        this.find_bar.clear_search_context ();
        this.left_stack.set_visible_child_name ("breadcrumbs");
        this.source_view.grab_focus (); // Возвращаем фокус ввода в сам редактор кода
    }

    public void update_diagnostics (int errors, int warnings) {
        this.diagnostic_bar.update_diagnostics (errors, warnings);
    }

    public void update_breadcrumbs (Gee.List<SourceNodeItem?> crumbs) {
        breadcrumps_bar.update_breadcrumbs (crumbs);
    }

    public void update_position (int line, int col, int selection_len = 0) {
        if (selection_len > 0) {
            pos_label.label = "%d:%d (%d selected)".printf (line + 1, col + 1, selection_len);
        } else {
            pos_label.label = "%d:%d".printf (line + 1, col + 1);
        }
    }

    public void update_mode (bool overwrite) {
        mode_label.label = overwrite ? "OVR" : "INS";
    }
}