/*
*/
public interface Iide.RpcTransport : GLib.Object {
    // Сигналы, которые обязан генерировать любой транспорт
    public signal void message_received (string json_payload);
    public signal void stderr_received (string log_line);
    public signal void unexpected_crash ();

    // Методы управления жизненным циклом канала
    public abstract bool init_channel (string[] command, string? workspace_root);
    public abstract async void write_message_async (string payload) throws GLib.Error;
    public abstract async void terminate_async ();
}

// Контейнер, удерживающий контекст отправляемого пакета и колбэк асинхронного метода
public class Iide.RpcWriteTask : GLib.Object {
    public string payload { get; set; }
    
    // Объявляем как обычное приватное поле-указатель, 
    // полностью избавляясь от логики ARC-владения свойствами!
    private SourceFunc callback_func;

    public RpcWriteTask (string payload, owned SourceFunc callback) {
        this.payload = payload;
        this.callback_func = (owned) callback;
    }

    // Открытый метод для вызова сохраненного фонового потока
    public void resume () {
        this.callback_func ();
    }
}
