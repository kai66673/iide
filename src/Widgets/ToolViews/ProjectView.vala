using Gtk;

public class Iide.FileTreeView : Box {
    private ColumnView column_view;
    private SingleSelection selection;
    private GLib.File? _root_directory = null;
    private CustomSorter sorter;

    public signal void file_activated (FileItem item);

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

            // Если корень есть, строим дерево
            var tree_model = new TreeListModel (sorted_root, false, false, (item) => {
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

    public FileTreeView (GLib.File? root_dir = null) {
        Object (orientation : Orientation.VERTICAL);

        // Инициализируем View без модели
        column_view = new ColumnView (null);
        // Скрываем заголовок
        column_view.get_first_child ().set_visible (false);

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

        // Безопасно устанавливаем корень (даже если это null)
        this.root_directory = root_dir;
    }

    private GLib.ListStore create_file_model (GLib.File dir) {
        var store = new GLib.ListStore (typeof (FileItem));
        try {
            // Запрашиваем только нужные атрибуты
            var enumerator = dir.enumerate_children ("standard::display-name,standard::type,standard::icon", 0, null);
            GLib.FileInfo info;
            while ((info = enumerator.next_file (null)) != null) {
                store.append (new FileItem (dir.get_child (info.get_name ()), info));
            }
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
            var icon = new Image ();
            var label = new Label ("");

            box.append (icon);
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
            var icon = box.get_first_child () as Image;
            var label = icon.get_next_sibling () as Label;

            expander.list_row = tree_row;
            if (file_item != null) {
                label.label = file_item.name;
                icon.icon_name = file_item.is_directory ? "folder" : "text-x-generic";

                if (!file_item.is_directory) {
                    var click = new Gtk.GestureClick ();
                    click.released.connect (() => {
                        file_activated (file_item);
                    });
                    box.add_controller (click);
                }
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
                is_directory : info.get_file_type () == GLib.FileType.DIRECTORY
        );
    }
}
