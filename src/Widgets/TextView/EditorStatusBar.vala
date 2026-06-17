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
        this.breadcrumps_bar.hexpand = true;
        this.breadcrumps_bar.update_file_path (GLib.File.new_for_uri (source_view.uri),
                                          GLib.File.new_for_path (ProjectManager.get_instance ().get_workspace_root_path ()));

        this.find_bar = new FindBar (source_view);
        this.find_bar.hexpand = true;

        // ===================================================================
        // Оборачиваем крошки в скрытый скролл!
        // ===================================================================
        var breadcrumbs_scroll = new Gtk.ScrolledWindow ();
        breadcrumbs_scroll.set_child (this.breadcrumps_bar);
        
        // Отключаем видимость полос прокрутки, чтобы они не загромождали статус-бар [INDEX]
        breadcrumbs_scroll.hscrollbar_policy = Gtk.PolicyType.EXTERNAL; 
        breadcrumbs_scroll.vscrollbar_policy = Gtk.PolicyType.NEVER;
        
        // Задаем выравнивание, чтобы скролл не растягивался насильно
        breadcrumbs_scroll.halign = Gtk.Align.FILL;
        breadcrumbs_scroll.valign = Gtk.Align.CENTER;
        breadcrumbs_scroll.hexpand = true;

        this.left_stack = new Gtk.Stack ();
        // Настраиваем красивую плавную анимацию скольжения (Slide) при переключении
        this.left_stack.transition_type = Gtk.StackTransitionType.SLIDE_LEFT_RIGHT;
        this.left_stack.transition_duration = 200; // 200 миллисекунд
        this.left_stack.add_named (breadcrumbs_scroll, "breadcrumbs");
        this.left_stack.add_named (this.find_bar, "find");
        this.left_stack.hexpand = true;
        this.append (this.left_stack);

        // При запросе Esc из панели поиска возвращаем хлебные крошки
        this.find_bar.close_requested.connect (() => {
            this.hide_search_bar ();
        });

        // На всякий случай также докручиваем принудительно через микро-задержку в Idle
        source_view.buffer.notify["cursor-position"].connect (() => {
            Idle.add (() => {
                this.scroll_breadcrumbs_to_end (breadcrumbs_scroll);
                return Source.REMOVE;
            });
        });

        // spacer
        var spacer_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 2);
        spacer_box.hexpand = false;
        this.append (spacer_box);

        // Правая часть: Статистика
        var info_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);

        mode_label = new Gtk.Label ("INS");
        mode_label.add_css_class ("dim-label");
        mode_label.height_request = 24;
        mode_label.width_request = 24;

        pos_label = new Gtk.Label ("1:1");
        pos_label.width_request = 64;

        info_box.append (mode_label);
        info_box.append (pos_label);
        this.append (info_box);

        diagnostic_bar = new DiagnosticsBar (source_view);
        diagnostic_bar.width_request = 64;

        // Добавляем в инфо-бокс перед позицией курсора
        info_box.prepend (diagnostic_bar);
    }

    private void scroll_breadcrumbs_to_end (Gtk.ScrolledWindow scroll_widget) {
        var adj = scroll_widget.get_hadjustment ();
        if (adj != null) {
            // Вычисляем максимальное правое положение: верхняя граница минус размер страницы [INDEX]
            double max_val = adj.get_upper () - adj.get_page_size ();
            if (max_val > 0) {
                // Мгновенно и без рывков сдвигаем видимую область в самый конец (к имени текущего метода) [INDEX]
                adj.set_value (max_val); 
            }
        }
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

    public void update_diagnostics (string server_name, int errors, int warnings) {
        this.diagnostic_bar.update_diagnostics (server_name, errors, warnings);
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