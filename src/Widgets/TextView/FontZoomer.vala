using Gtk;
using GtkSource;
using GLib;

public class FontZoomer : Object {
    private View src_view;
    private int zoom_level;
    private Iide.SettingsService settings;
    public signal void zoom_changed(int level);

    public FontZoomer(View src_view) {
        this.src_view = src_view;
        this.settings = Iide.SettingsService.get_instance();

        if (!this.src_view.has_css_class("text-view")) {
            this.src_view.add_css_class("text-view");
        }

        this.zoom_level = settings.editor_font_size;
        if (this.zoom_level < FontSizeHelper.MIN_ZOOM_LEVEL || this.zoom_level > FontSizeHelper.MAX_ZOOM_LEVEL) {
            this.zoom_level = FontSizeHelper.DEFAULT_ZOOM_LEVEL;
        }
        this.src_view.add_css_class("zoom-" + zoom_level.to_string());

        var scroll_controller = new EventControllerScroll(EventControllerScrollFlags.VERTICAL);
        scroll_controller.scroll.connect((dx, dy) => {
            var event = scroll_controller.get_current_event();
            if (event == null)return false;

            var modifiers = event.get_modifier_state();
            if ((modifiers & Gdk.ModifierType.CONTROL_MASK) != 0) {
                if (dy < 0) {
                    zoom_in();
                } else if (dy > 0) {
                    zoom_out();
                }
                return true;
            }
            return false;
        });

        this.src_view.add_controller(scroll_controller);
    }

    public void zoom_in() {
        if (zoom_level < FontSizeHelper.MAX_ZOOM_LEVEL) {
            src_view.remove_css_class("zoom-" + zoom_level.to_string());
            zoom_level++;
            src_view.add_css_class("zoom-" + zoom_level.to_string());
            settings.editor_font_size = zoom_level;
            zoom_changed(zoom_level);
        }
    }

    public void zoom_out() {
        if (zoom_level > FontSizeHelper.MIN_ZOOM_LEVEL) {
            src_view.remove_css_class("zoom-" + zoom_level.to_string());
            zoom_level--;
            src_view.add_css_class("zoom-" + zoom_level.to_string());
            settings.editor_font_size = zoom_level;
            zoom_changed(zoom_level);
        }
    }

    public void zoom_reset() {
        src_view.remove_css_class("zoom-" + zoom_level.to_string());
        zoom_level = FontSizeHelper.DEFAULT_ZOOM_LEVEL;
        src_view.add_css_class("zoom-" + zoom_level.to_string());
        settings.editor_font_size = zoom_level;
        zoom_changed(zoom_level);
    }

    public void set_zoom_level(int level) {
        if (level < FontSizeHelper.MIN_ZOOM_LEVEL || level > FontSizeHelper.MAX_ZOOM_LEVEL) {
            return;
        }
        if (zoom_level == level) {
            return;
        }
        src_view.remove_css_class("zoom-" + zoom_level.to_string());
        zoom_level = level;
        src_view.add_css_class("zoom-" + zoom_level.to_string());
        zoom_changed(zoom_level);
    }

    public int get_zoom_level() {
        return zoom_level;
    }
}
