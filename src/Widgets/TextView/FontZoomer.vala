using Gtk;
using GtkSource;

public class FontZoomer : Object {
    private View view;
    private CssProvider css_provider;
    private int current_size = 11;

    public FontZoomer(View source_view) {
        this.view = source_view;
        this.css_provider = new CssProvider();

        // В GTK4 провайдер лучше добавлять к дисплею или через Gtk.Widget.add_css_class
        // Но для точечного управления конкретным виджетом используем этот метод:
        this.view.get_style_context().add_provider(
                                                   this.css_provider,
                                                   Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        );

        // Создаем контроллер прокрутки
        var scroll_controller = new EventControllerScroll(EventControllerScrollFlags.VERTICAL);

        // В GTK4 сигнал scroll возвращает boolean
        scroll_controller.scroll.connect((dx, dy) => {
            // Получаем текущее событие из контроллера
            var event = scroll_controller.get_current_event();
            if (event == null)return false;

            // Проверяем модификаторы события
            var modifiers = event.get_modifier_state();

            if ((modifiers & Gdk.ModifierType.CONTROL_MASK) != 0) {
                if (dy < 0) {
                    zoom_in();
                } else if (dy > 0) {
                    zoom_out();
                }
                return true; // Событие обработано, скролл текста блокируется
            }

            return false; // Ctrl не зажат, обычный скролл
        });

        // Добавляем контроллер к GtkSourceView
        this.view.add_controller(scroll_controller);

        update_css();
    }

    public void zoom_in() {
        current_size++;
        update_css();
    }

    public void zoom_out() {
        if (current_size > 5) {
            current_size--;
            update_css();
        }
    }

    public void zoom_reset() {
        current_size = 11;
        update_css();
    }

    private void update_css() {
        // В GTK4 для GtkSourceView селектор 'textview' по-прежнему актуален
        string css = "textview { font-size: %dpt; }".printf(current_size);

        // В GTK4 load_from_data принимает строку напрямую (в Vala как string)
        css_provider.load_from_string(css);
    }
}
