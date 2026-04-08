using Gtk;
using GtkSource;

public class MyProposal : Object, CompletionProposal {
    public string label { get; construct; }
    public MyProposal (string text) { Object (label: text); }
}

public class MyProvider : Object, CompletionProvider {
    private string[] words = { "vala", "valgalla", "volt", "gtk3", "gtk4", "gtk345", "sourceview", "linux", "manjaro" };

    // 1. Исправляем авто-показ
    public virtual CompletionActivation get_activation (CompletionContext context) {
        // Разрешаем показ при наборе текста (INTERACTIVE)
        // и принудительный показ по Ctrl+Space (USER_REQUESTED)
        return CompletionActivation.INTERACTIVE | CompletionActivation.USER_REQUESTED;
    }

    public virtual async GLib.ListModel populate_async (CompletionContext context, GLib.Cancellable? cancellable) throws GLib.Error {
        // Просто вызываем нашу функцию генерации списка
        return create_filtered_model (context.get_word ());
    }

    public virtual void display (CompletionContext context, CompletionProposal proposal, CompletionCell cell) {
        var p = (MyProposal) proposal;
        if (cell.column == CompletionColumn.TYPED_TEXT) {
            cell.text = p.label;
        }
    }

    // 2. Исправляем вставку (сдвиг)
    public virtual void activate (CompletionContext context, CompletionProposal proposal) {
        var view = context.get_view ();
        var buffer = view.get_buffer ();

        TextIter start, end;

        // Пытаемся получить границы, которые GSV уже определил как "слово под курсором"
        if (context.get_bounds (out start, out end)) {
            // Если границы найдены, просто удаляем этот участок
            buffer.delete (ref start, ref end);
        } else {
            // Если границ нет (редкий случай), используем старый метод, но аккуратно
            buffer.get_iter_at_mark (out start, buffer.get_insert ());
            end = start;
            string? word = context.get_word ();
            if (word != null && word != "") {
                start.backward_chars (word.char_count ());
                buffer.delete (ref start, ref end);
            }
        }

        // Вставляем слово
        var p = (MyProposal) proposal;
        buffer.insert (ref start, p.label, -1);
    }

    // Обязательные методы-заглушки
    public virtual void refilter (CompletionContext context, GLib.ListModel model) {
        // Когда пользователь вводит текст, GSV передает нам текущую модель (наш ListStore).
        // Мы очищаем его и заполняем заново исходя из нового слова.
        var list = model as GLib.ListStore;
        if (list == null)return;

        list.remove_all ();
        string? word = context.get_word ();

        if (word != null && word.length >= 2) {
            string filter_word = word.down ();
            foreach (var w in words) {
                if (w.has_prefix (filter_word)) {
                    list.append (new MyProposal (w));
                }
            }
        }

        if (model.get_n_items () == 0) {
            context.get_completion ().hide ();
        }
    }

    public virtual string ? get_title () { return "Simple"; }
    public virtual int get_priority (CompletionContext context) { return 100; }
    public virtual bool is_running (CompletionContext context) { return true; }

    // Вынесем логику создания в отдельный метод для удобства populate_async
    private GLib.ListStore create_filtered_model (string? word) {
        var list = new GLib.ListStore (typeof (MyProposal));
        if (word != null && word.length >= 2) {
            string filter_word = word.down ();
            foreach (var w in words) {
                if (w.has_prefix (filter_word)) {
                    list.append (new MyProposal (w));
                }
            }
        }
        return list;
    }
}
