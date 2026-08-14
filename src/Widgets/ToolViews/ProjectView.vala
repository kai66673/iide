using Gtk;

public class Iide.FileTreeView : Box {
    private ColumnView column_view;
    private SingleSelection selection;
    private GLib.File? _root_directory = null;
    private CustomSorter sorter;

    public signal void file_activated (FileItem item);
    public signal void file_rename_requested (FileItem item);
    public signal void create_entry_requested (FileItem item, bool is_directory);

    private Gtk.Popover? context_popover = null;
    private FileItem? context_item = null;
    private Gtk.Button? rename_button = null;

    // Свойство с поддержкой null
    public GLib.File? root_directory {
        get { return _root_directory; }
        set {
            _root_directory = value;

            if (_root_directory == null) {
                // Если передан null, просто очищаем модель во View
                column_view.model = null;
                selection = null;
                return;
            }

            // Базовая модель с сортировкой
            var root_store = create_file_model (_root_directory);
            var sorted_root = new SortListModel (root_store, sorter);

            // Каноничное дерево GTK4. Модель сама лениво дернет эту лямбду,
            // когда пользователь нажмет стрелочку на UI!
            var tree_model = new TreeListModel (sorted_root, false, false, (item) => {
                // ПРАВИЛЬНО: На входе всегда оригинальный элемент модели (FileItem)
                var file_item = item as FileItem;
                
                if (file_item != null && file_item.is_directory) {
                    var child_store = create_file_model (file_item.file);
                    return new SortListModel (child_store, sorter);
                }
                return null;
            });

            selection = new SingleSelection (tree_model);
            column_view.model = selection;
        }
    }

    /**
     * Перестраивает дерево проекта с диска, сохраняя развёрнутые директории.
     */
    public void refresh () {
        var root = this._root_directory;
        if (root == null || this.selection == null)
            return;

        // 1. Запоминаем, какие директории сейчас развёрнуты
        var expanded_uris = new Gee.HashSet<string> ();
        var current_tree = this.selection.model as TreeListModel;
        if (current_tree != null) {
            for (uint i = 0; i < current_tree.get_n_items (); i++) {
                this.collect_expanded_uris (current_tree.get_row (i), expanded_uris);
            }
        }

        // 2. Перестраиваем модель с диска
        this.root_directory = root;

        // 3. Восстанавливаем развёрнутые директории
        var new_tree = this.selection.model as TreeListModel;
        if (new_tree != null) {
            for (uint i = 0; i < new_tree.get_n_items (); i++) {
                this.expand_uri_path (new_tree.get_row (i), expanded_uris);
            }
        }
    }

    /**
     * Разворачивает в дереве путь до указанной директории (включая её саму),
     * чтобы после создания файла/папки новый элемент был виден.
     */
    public void expand_to_directory (GLib.File dir) {
        var tree = this.selection.model as TreeListModel;
        if (tree == null)
            return;

        string target_uri = dir.get_uri ();
        for (uint i = 0; i < tree.get_n_items (); i++) {
            this.expand_to_uri (tree.get_row (i), target_uri);
        }
    }

    /**
     * Раскрывает дерево до указанного элемента (раскрывает его родителя),
     * затем выделяет сам элемент и прокручивает к нему список.
     * Нужно для подсветки только что созданного файла/папки.
     */
    public void select_file (GLib.File file) {
        var tree = this.selection.model as TreeListModel;
        if (tree == null)
            return;

        // Сначала раскрываем родителя, чтобы элемент появился в плоской модели
        var parent = file.get_parent ();
        if (parent != null)
            this.expand_to_directory (parent);

        string target_uri = file.get_uri ();
        for (uint i = 0; i < tree.get_n_items (); i++) {
            var item = tree.get_row (i).get_item () as FileItem;
            if (item != null && item.file.get_uri () == target_uri) {
                this.selection.selected = i;
                this.column_view.scroll_to (i, null, Gtk.ListScrollFlags.SELECT, null);
                return;
            }
        }
    }

    private void expand_to_uri (Gtk.TreeListRow row, string target_uri) {
        if (row == null)
            return;

        var item = row.get_item () as FileItem;
        if (item == null || !item.is_directory)
            return;

        // Директория — предок или сама цель: разворачиваем и идём глубже.
        // Сравниваем по префиксу с учётом разделителя пути, чтобы
        // file:///a/b не совпадал с file:///a/bc.
        string uri = item.file.get_uri ();
        if (!target_uri.has_prefix (uri))
            return;
        string rest = target_uri[uri.length:];
        if (rest != "" && !rest.has_prefix ("/"))
            return;

        if (row.is_expandable ())
            row.set_expanded (true);

        var children = row.get_children ();
        if (children != null) {
            for (uint i = 0; i < children.get_n_items (); i++) {
                this.expand_to_uri (row.get_child_row (i), target_uri);
            }
        }
    }

    private void collect_expanded_uris (Gtk.TreeListRow row, Gee.HashSet<string> acc) {
        if (row == null)
            return;

        var item = row.get_item () as FileItem;
        if (item == null)
            return;

        if (row.is_expandable () && row.expanded) {
            acc.add (item.file.get_uri ());
            var children = row.get_children ();
            if (children != null) {
                for (uint i = 0; i < children.get_n_items (); i++) {
                    this.collect_expanded_uris (row.get_child_row (i), acc);
                }
            }
        }
    }

    private void expand_uri_path (Gtk.TreeListRow row, Gee.HashSet<string> uris) {
        if (row == null)
            return;

        var item = row.get_item () as FileItem;
        if (item == null)
            return;

        if (uris.contains (item.file.get_uri ()) && row.is_expandable ()) {
            // Разворачиваем директорию — дети загружаются лениво
            row.set_expanded (true);
            var children = row.get_children ();
            if (children != null) {
                for (uint i = 0; i < children.get_n_items (); i++) {
                    this.expand_uri_path (row.get_child_row (i), uris);
                }
            }
        }
    }

    public FileTreeView (GLib.File? root_dir = null) {
        Object (orientation : Orientation.VERTICAL);

        // Инициализируем View без модели
        column_view = new ColumnView (null);
        // Скрываем заголовок
        column_view.get_first_child ().set_visible (false);

        // Устанавливаем корневой каталог, если передан
        if (root_dir != null) {
            root_directory = root_dir;
        }

        setup_view ();
    }

    public void set_root_file (GLib.File? root_dir) {
        root_directory = root_dir;
    }

    private void setup_view () {
        var column = new ColumnViewColumn (null, create_factory ());
        column.expand = true;
        sorter = new CustomSorter ((a, b) => {
            var fi1 = a as FileItem;
            var fi2 = b as FileItem;
            if (fi1 == null || fi2 == null)return 0;

            // Сначала сравниваем тип: директории перед файлами
            if (fi1.is_directory != fi2.is_directory) {
                return fi1.is_directory ? -1 : 1;
            }
            // Затем по имени
            return strcmp (fi1.name.down (), fi2.name.down ());
        });
        column.sorter = sorter;
        column_view.append_column (column);

        var scroll = new ScrolledWindow ();
        scroll.vexpand = true;
        scroll.set_child (column_view);
        this.append (scroll);

        column_view.activate.connect ((pos) => {
            var item = selection.get_item (pos) as TreeListRow;
            if (item != null) {
                var file_item = item.get_item () as FileItem;
                if (file_item != null) {
                    file_activated (file_item);
                }
            }
        });

        setup_context_menu ();
    }

    private void setup_context_menu () {
        var menu_box = new Gtk.Box (Orientation.VERTICAL, 0);

        var new_file_button = new Gtk.Button.with_label (_("New File…"));
        new_file_button.add_css_class ("flat");
        new_file_button.hexpand = true;
        new_file_button.halign = Gtk.Align.FILL;
        new_file_button.clicked.connect (() => {
            if (this.context_popover != null)
                this.context_popover.popdown ();
            if (this.context_item != null)
                this.create_entry_requested (this.context_item, false);
        });
        menu_box.append (new_file_button);

        var new_dir_button = new Gtk.Button.with_label (_("New Directory…"));
        new_dir_button.add_css_class ("flat");
        new_dir_button.hexpand = true;
        new_dir_button.halign = Gtk.Align.FILL;
        new_dir_button.clicked.connect (() => {
            if (this.context_popover != null)
                this.context_popover.popdown ();
            if (this.context_item != null)
                this.create_entry_requested (this.context_item, true);
        });
        menu_box.append (new_dir_button);

        menu_box.append (new Gtk.Separator (Orientation.HORIZONTAL));

        this.rename_button = new Gtk.Button.with_label (_("Rename…"));
        this.rename_button.add_css_class ("flat");
        this.rename_button.hexpand = true;
        this.rename_button.halign = Gtk.Align.FILL;
        this.rename_button.clicked.connect (() => {
            if (this.context_popover != null)
                this.context_popover.popdown ();
            if (this.context_item != null)
                this.file_rename_requested (this.context_item);
        });
        menu_box.append (this.rename_button);

        this.context_popover = new Gtk.Popover ();
        this.context_popover.child = menu_box;
        // Родителем делаем стабильный виджет дерева, а позицию задаём
        // координатами клика относительно него (см. open_context_menu)
        this.context_popover.set_parent (this.column_view);
    }

    private void open_context_menu (Gtk.Widget anchor, FileItem item, double x, double y) {
        this.context_item = item;

        // Ренейм пока поддерживается только для файлов
        if (this.rename_button != null)
            this.rename_button.sensitive = !item.is_directory;

        double dx = x, dy = y;
        anchor.translate_coordinates (this.column_view, x, y, out dx, out dy);

        this.context_popover.set_pointing_to (Gdk.Rectangle () {
            x = (int) dx,
            y = (int) dy,
            width = 1,
            height = 1
        });
        this.context_popover.popup ();
    }

    private GLib.ListStore create_file_model (GLib.File dir) {
        var store = new GLib.ListStore (typeof (FileItem));
        try {
            // Запрашиваем только нужные атрибуты
            var enumerator = dir.enumerate_children ("standard::display-name,standard::type", 0, null);

            if (enumerator == null) {
                return store;
            }

            while (true) {
                GLib.FileInfo? info = null;
                
                // Защита №2: Изолируем Си-сбои итератора GIO внутри индивидуального блока try-catch!
                try {
                    info = enumerator.next_file (null);
                } catch (Error e) {
                    debug (@"Skipping corrupted file node inside $(dir.get_path()): $(e.message)");
                    continue; // Пропускаем сломанный файл и идем к следующему!
                }

                // Конец списка папки
                if (info == null) break;

                // Защита №3: Проверяем валидность имени перед созданием FileItem
                string name = info.get_name ();
                if (name != null && name != "") {
                    store.append (new FileItem (dir.get_child (name), info));
                }
            }
            
            enumerator.close (null);
        } catch (Error e) {
            // Ошибка может возникнуть при отсутствии прав доступа
            debug ("Cannot read directory: %s", e.message);
        }
        return store;
    }

    private ListItemFactory create_factory () {
        var factory = new SignalListItemFactory ();

        factory.setup.connect ((list_item) => {
            var item = (Gtk.ListItem) list_item;
            var expander = new TreeExpander ();
            var box = new Box (Orientation.HORIZONTAL, 6);
            var icon_box = new Box (Orientation.HORIZONTAL, 2);
            icon_box.set_size_request (20, 20);
            var label = new Label ("");

            box.append (icon_box);
            box.append (label);
            expander.set_child (box);
            item.set_child (expander);
        });

        factory.bind.connect ((list_item) => {
            var item = (Gtk.ListItem) list_item;
            var tree_row = item.get_item () as TreeListRow;
            if (tree_row == null)return;

            var file_item = tree_row.get_item () as FileItem;
            var expander = item.get_child () as TreeExpander;
            var box = expander.get_child () as Box;
            var icon_box = box.get_first_child () as Box;
            var label = icon_box.get_next_sibling () as Label;

            expander.list_row = tree_row;
            if (file_item != null) {
                label.label = file_item.name;
                if (file_item.is_directory) {
                    icon_box.append (ImageFactory.folder_image ());
                } else {
                    icon_box.append (ImageFactory.create_for_file (file_item.file));
                }

                if (!file_item.is_directory) {
                    var click = new Gtk.GestureClick ();
                    click.set_button (1);
                    click.released.connect (() => {
                        file_activated (file_item);
                    });
                    box.add_controller (click);
                }

                // Правый клик — контекстное меню (New File…/New Directory…/Rename…)
                var right_click = new Gtk.GestureClick ();
                right_click.set_button (3);
                right_click.pressed.connect ((n_press, x, y) => {
                    this.open_context_menu (box, file_item, x, y);
                });
                box.add_controller (right_click);
            }
        });

        return factory;
    }
}

// Вспомогательный класс данных
public class Iide.FileItem : Object {
    public GLib.File file { get; construct; }
    public string name { get; construct; }
    public bool is_directory { get; construct; }

    public FileItem (GLib.File file, GLib.FileInfo info) {
        Object (
                file : file,
                name : info.get_display_name (),
                is_directory: info.get_file_type () == GLib.FileType.DIRECTORY
        );
    }
}