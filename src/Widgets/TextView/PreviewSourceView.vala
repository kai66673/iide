/*
*/

public class Iide.PreviewSourceView : GtkSource.View {
    public PreviewSourceView (string code, GtkSource.View main_view) {
        // 1. Первой строкой создаем объект и сразу инициализируем его свойства
        Object (
            buffer: new GtkSource.Buffer (null)
        );

        // 2. Теперь можно выполнять любую логику, буфер уже создан
        var preview_buffer = this.buffer as GtkSource.Buffer;

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

        // Синхронизируем синтаксическую подсветку и тему
        var main_buffer = main_view.buffer as GtkSource.Buffer;
        if (main_buffer != null && preview_buffer != null) {
            preview_buffer.set_language (main_buffer.get_language ());
            preview_buffer.set_style_scheme (main_buffer.get_style_scheme ());
        }

        // Загружаем и обрезаем скрытый код
        if (preview_buffer != null) {
            preview_buffer.set_text (code, -1);
        }

        // Настраиваем отступы виджета
        this.margin_top = 1;
        this.margin_bottom = 1;
        this.margin_start = 1;
        this.margin_end = 1;

        this.set_size_request (main_view.get_width () * 3 / 4, -1);

        var zoom_level = SettingsService.get_instance ().editor_font_size;
        if (zoom_level < FontSizeHelper.MIN_ZOOM_LEVEL || zoom_level > FontSizeHelper.MAX_ZOOM_LEVEL) {
            zoom_level = FontSizeHelper.DEFAULT_ZOOM_LEVEL;
        }
        this.add_css_class("text-view");
        this.add_css_class("zoom-" + zoom_level.to_string());
    }
}