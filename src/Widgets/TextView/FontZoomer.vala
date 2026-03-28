using Gtk;
using GtkSource;
using GLib;

public class FontZoomer : Object {
    private View view;
    private int zoom_level = 6;
    private Iide.SettingsService settings;

    public FontZoomer(View source_view) {
        this.view = source_view;
        this.settings = Iide.SettingsService.get_instance ();

        if (!this.view.has_css_class("text-view")) {
            this.view.add_css_class("text-view");
        }

        var scroll_controller = new EventControllerScroll(EventControllerScrollFlags.VERTICAL);
        scroll_controller.scroll.connect((dx, dy) => {
            var event = scroll_controller.get_current_event();
            if (event == null) return false;

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

        this.view.add_controller(scroll_controller);
    }

    public void zoom_in() {
        if (zoom_level < 15) {
            view.remove_css_class("zoom-" + zoom_level.to_string());
            zoom_level++;
            view.add_css_class("zoom-" + zoom_level.to_string());
            save_zoom_level ();
        }
    }

    public void zoom_out() {
        if (zoom_level > 1) {
            view.remove_css_class("zoom-" + zoom_level.to_string());
            zoom_level--;
            view.add_css_class("zoom-" + zoom_level.to_string());
            save_zoom_level ();
        }
    }

    public void zoom_reset() {
        view.remove_css_class("zoom-" + zoom_level.to_string());
        zoom_level = 6;
        view.add_css_class("zoom-" + zoom_level.to_string());
        save_zoom_level ();
    }

    public void set_font_size (double size) {
        settings.editor_font_size = size;
    }

    private void save_zoom_level () {
        settings.editor_font_size = zoom_level;
    }
}
