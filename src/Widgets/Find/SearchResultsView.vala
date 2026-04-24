public class Iide.SearchResultItem : Gtk.Box {
    private Gtk.Label name_label;
    private Gtk.Label path_label;
    private Gtk.Image icon;

    public SearchResultItem() {
        Object(orientation: Gtk.Orientation.HORIZONTAL, spacing: 12);
        this.margin_start = 8;
        this.margin_end = 8;
        this.margin_top = 6;
        this.margin_bottom = 6;

        icon = new Gtk.Image();
        icon.set_size_request(20, 20);

        var text_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 2);
        text_box.hexpand = true;

        name_label = new Gtk.Label(null);
        name_label.xalign = 0;
        name_label.add_css_class("title-5");
        name_label.hexpand = true;

        path_label = new Gtk.Label(null);
        path_label.add_css_class("dim-label");
        path_label.add_css_class("caption");
        path_label.xalign = 0;
        path_label.ellipsize = Pango.EllipsizeMode.START;
        path_label.hexpand = true;

        text_box.append(name_label);
        text_box.append(path_label);

        this.append(icon);
        this.append(text_box);
    }

    private string escape_pango(string text) {
        return text
                .replace("&", "&amp;")
                .replace("<", "&lt;")
                .replace(">", "&gt;");
    }

    private string highlight_matches(string text, Gee.List<MatchRange>? matches) {
        var escaped = escape_pango(text);

        if (matches == null || matches.size == 0) {
            return escaped;
        }

        var sb = new StringBuilder();
        int pos = 0;

        foreach (var m in matches) {
            if (m.start > pos) {
                sb.append(escaped.substring(pos, m.start - pos));
            }
            if (m.end > m.start && m.end <= (int) escaped.length) {
                sb.append("<span weight=\"bold\" background=\"#ffd700\" color=\"#000000\">");
                sb.append(escaped.substring(m.start, m.end - m.start));
                sb.append("</span>");
            }
            pos = m.end;
        }

        if (pos < (int) escaped.length) {
            sb.append(escaped.substring(pos));
        }

        return sb.str;
    }

    public void bind_search_result(SearchResult result) {
        var highlighted_name = highlight_matches(result.line_content, result.matches);
        var line_prefix = result.line_number == -1 ? "" : (result.line_number + 1).to_string() + ": ";
        name_label.set_markup(line_prefix + highlighted_name);
        path_label.set_label(result.relative_path);
        if (result.icon_name == null) {
            icon.hide();
        } else {
            icon.set_from_icon_name(result.icon_name);
        }
    }
}

// Наследуемся от Box — это безопаснее и проще
public class Iide.SearchResultsView : Gtk.Box {
    private DocumentManager document_manager = DocumentManager.get_instance();
    public Gtk.ListView list_view; // ListView теперь ВНУТРИ
    public Gtk.SingleSelection selection;
    private GLib.ListStore results;

    private const int MAX_RESULTS = 100;

    public SearchResultsView() {
        Object(orientation: Gtk.Orientation.VERTICAL, spacing: 0);

        results = new GLib.ListStore(typeof (SearchResult));
        selection = new Gtk.SingleSelection(results);

        var factory = new Gtk.SignalListItemFactory();
        factory.setup.connect((item) => {
            var list_item = item as Gtk.ListItem;
            list_item.child = new SearchResultItem();
        });

        factory.bind.connect((item) => {
            var list_item = item as Gtk.ListItem;
            var item_box = list_item.child as SearchResultItem;
            var result = (SearchResult) list_item.item;
            item_box.bind_search_result(result);
        });

        // Создаем ListView как внутренний элемент
        list_view = new Gtk.ListView(selection, factory);
        list_view.hexpand = true;
        list_view.vexpand = true;
        list_view.show_separators = true;

        // Добавляем ListView в наш Box
        var scrolled = new Gtk.ScrolledWindow();
        scrolled.child = list_view;
        this.append(scrolled);
    }

    // В методах навигации просто меняем 'this' на 'list_view'
    public void select_up() {
        if (selection.selected > 0) {
            selection.selected -= 1;
            list_view.scroll_to(selection.selected, Gtk.ListScrollFlags.NONE, null);
        }
    }

    public void select_down() {
        if (selection.selected < (int) results.n_items - 1) {
            selection.selected += 1;
            list_view.scroll_to(selection.selected, Gtk.ListScrollFlags.NONE, null);
        }
    }

    public void update_results(Gee.List<SearchResult>? new_results) {
        if (new_results == null || new_results.size == 0) {
            results.splice(0, results.n_items, new SearchResult[0]);
            return;
        }

        var show_count = new_results.size;
        if (show_count > MAX_RESULTS) {
            show_count = MAX_RESULTS;
        }

        var items = new SearchResult[show_count];
        for (var i = 0; i < show_count; i++) {
            items[i] = new_results[i];
        }
        update_result_list(items);
    }

    public void update_result_list(SearchResult[] items) {
        results.splice(0, results.n_items, items);
        if (items.length > 0) {
            selection.selected = 0;
        }
    }

    public bool open_selected() {
        var index = (int) selection.selected;
        if (index >= 0 && index < results.n_items) {
            var result = results.get_item(index) as SearchResult;
            var file = GLib.File.new_for_path(result.file_path);

            int start_col = 0;
            int end_col = 0;
            if (result.matches != null && result.matches.size > 0) {
                start_col = result.matches[0].start;
                end_col = result.matches[0].end;
            }

            document_manager.open_document_with_selection(file, result.line_number, start_col, end_col, null);
            return true;
        }
        return false;
    }
}