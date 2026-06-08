/*
*/

public class Iide.PreviewSourceView : GtkSource.View {
    public PreviewSourceView.with_buffer (GtkSource.Buffer prefilled_buffer, GtkSource.View main_view) {
        // Передаем уже наполненный через RichText буфер в базовый Object
        Object (buffer: prefilled_buffer);

        // Отключаем интерактивность
        this.editable = false;
        this.cursor_visible = false;
        this.sensitive = false;

        // Отключаем элементы интерфейса
        this.show_line_numbers = false;
        this.highlight_current_line = false;
        this.auto_indent = false;
        this.insert_spaces_instead_of_tabs = main_view.insert_spaces_instead_of_tabs;
        this.tab_width = main_view.tab_width;

                // Настраиваем отступы виджета
        this.margin_top = 1;
        this.margin_bottom = 1;
        this.margin_start = 1;
        this.margin_end = 1;

        this.set_size_request (main_view.get_width () * 8 / 9, -1);
        this.vexpand = true;

        var zoom_level = SettingsService.get_instance ().editor_font_size;
        if (zoom_level < FontSizeHelper.MIN_ZOOM_LEVEL || zoom_level > FontSizeHelper.MAX_ZOOM_LEVEL) {
            zoom_level = FontSizeHelper.DEFAULT_ZOOM_LEVEL;
        }
        this.add_css_class("text-view");
        this.add_css_class("zoom-" + zoom_level.to_string());
    }
}