using Gtk;
using Panel;

public class MyEditorPage : Panel.Widget {
    private Panel.SaveDelegate save_delegate;
    private TextBuffer buffer;

    public MyEditorPage (string title) {
        Object (kind: "editor");
        this.title = title;

        // Создаем текстовое поле
        var scrolled = new ScrolledWindow ();
        var text_view = new TextView ();
        this.buffer = text_view.buffer;
        scrolled.child = text_view;
        this.child = scrolled;

        // Инициализируем SaveDelegate
        this.save_delegate = new Panel.SaveDelegate ();

        // Подключаем сигнал сохранения
        this.save_delegate.save.connect (on_save);

        // Отслеживаем изменения в тексте
        this.buffer.changed.connect (() => {
            this.save_delegate.is_modified = true;
        });
    }

    // Метод, который вызывается системой для сохранения
    private async bool on_save (Panel.SaveDelegate delegate) {
        print ("Сохранение файла: %s...\n", this.title);

        // Имитация записи на диск
        // Здесь должна быть ваша логика записи GFile

        // После успешного сохранения сбрасываем флаг изменений
        this.save_delegate.is_modified = false;
        return true;
    }

    // Переопределяем метод получения делегата, чтобы Panel видела его
    public override Panel.SaveDelegate? get_save_delegate () {
        return this.save_delegate;
    }
}
