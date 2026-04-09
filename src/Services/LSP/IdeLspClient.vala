using GLib;
using Json;

public class Iide.IdeLspDiagnostic : GLib.Object {
    public int severity { get; set; default = 1; }
    public string message { get; set; default = ""; }
    public int start_line { get; set; default = 0; }
    public int start_column { get; set; default = 0; }
    public int end_line { get; set; default = 0; }
    public int end_column { get; set; default = 0; }

    public string to_string () {
        return "Diagnostic: (%d:%d-%d:%d) %s".printf (start_line, start_column, end_line, end_column, message);
    }
}

public class Iide.IdeLspCompletionItem : GLib.Object {
    public string label { get; set; default = ""; }
    public string? detail { get; set; }
    public string? documentation { get; set; }
    public int sort_text_priority { get; set; default = 0; }
    public int insert_text_priority { get; set; default = 0; }
    public string insert_text { get; set; default = ""; }
    public string? text_edit { get; set; }
    public int start_line { get; set; default = 0; }
    public int start_column { get; set; default = 0; }
    public int end_line { get; set; default = 0; }
    public int end_column { get; set; default = 0; }
    public IdeLspCompletionKind kind { get; set; default = IdeLspCompletionKind.TEXT; }
}

public enum Iide.IdeLspCompletionKind {
    TEXT = 1,
    METHOD = 2,
    FUNCTION = 3,
    CONSTRUCTOR = 4,
    FIELD = 5,
    VARIABLE = 6,
    CLASS = 7,
    INTERFACE = 8,
    MODULE = 9,
    PROPERTY = 10,
    UNIT = 11,
    VALUE = 12,
    ENUM = 13,
    KEYWORD = 14,
    SNIPPET = 15,
    COLOR = 16,
    FILE = 17,
    REFERENCE = 18,
    FOLDER = 19,
    ENUM_MEMBER = 20,
    CONSTANT = 21,
    STRUCT = 22,
    EVENT = 23,
    OPERATOR = 24,
    TYPE_PARAMETER = 25
}

public class Iide.IdeLspCompletionResult : GLib.Object {
    public Gee.ArrayList<IdeLspCompletionItem> items { get; set; }
    public bool is_incomplete { get; set; default = false; }
}


private class Iide.CallbackWrapper {
    public SourceFunc callback;
    public CallbackWrapper (owned SourceFunc cb) {
        this.callback = (owned) cb;
    }
}

public class Iide.IdeLspClient : GLib.Object {
    public signal void initialized ();
    public signal void diagnostics_received (string uri, Gee.ArrayList<IdeLspDiagnostic> diagnostics);
    public signal void completion_received (string uri, IdeLspCompletionResult result);
    public signal void error_occurred (string message);

    private SubprocessLauncher? launcher;
    private Subprocess? process;
    private InputStream? stdout_stream;
    private OutputStream? stdin_stream;

    private uint next_request_id = 1;
    private Gee.HashMap<int, Cancellable?> pending_requests;
    private bool server_initialized = false;
    private string? workspace_root;

    private uint8[] read_buffer;
    private Thread<void>? reader_thread;

    private bool is_writing = false;
    private bool is_writing_queue = false;
    private Gee.ArrayList<string> message_queue;
    private Gee.HashMap<int, string> pending_responses;

    private Gee.HashMap<int, CallbackWrapper> pending_callbacks;
    private Gee.HashMap<int, Json.Object> response_data;


    public IdeLspClient () {
        pending_requests = new Gee.HashMap<int, Cancellable?> ();
        pending_responses = new Gee.HashMap<int, string> ();
        message_queue = new Gee.ArrayList<string> ();
        read_buffer = new uint8[65536];

        pending_callbacks = new Gee.HashMap<int, CallbackWrapper> ();
        response_data = new Gee.HashMap<int, Json.Object> ();
    }

    private string build_request_json (string method, Json.Node? params) {
        var builder = new Json.Builder ();
        builder.begin_object ();
        builder.set_member_name ("jsonrpc");
        builder.add_string_value ("2.0");
        builder.set_member_name ("id");
        builder.add_int_value (next_request_id++);
        builder.set_member_name ("method");
        builder.add_string_value (method);
        builder.set_member_name ("params");
        if (params != null) {
            builder.add_value (params);
        } else {
            builder.begin_object ();
            builder.end_object ();
        }
        builder.end_object ();

        var generator = new Json.Generator ();
        generator.root = builder.get_root ();
        return generator.to_data (null);
    }

    private string build_notification_json (string method, Json.Node? params = null) {
        var builder = new Json.Builder ();
        builder.begin_object ();
        builder.set_member_name ("jsonrpc");
        builder.add_string_value ("2.0");
        builder.set_member_name ("method");
        builder.add_string_value (method);
        builder.set_member_name ("params");
        if (params != null) {
            builder.add_value (params);
        } else {
            builder.begin_object ();
            builder.end_object ();
        }
        builder.end_object ();

        var generator = new Json.Generator ();
        generator.root = builder.get_root ();
        return generator.to_data (null);
    }

    public async bool start_server (string command, string[] args, string? workspace_root, Json.Node? initialization_options = null) {
        this.workspace_root = workspace_root;

        try {
            var argv = new Gee.ArrayList<string> ();
            argv.add (command);
            foreach (var arg in args) {
                argv.add (arg);
            }

            launcher = new SubprocessLauncher (SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDIN_PIPE);
            process = launcher.spawnv (argv.to_array ());

            stdout_stream = process.get_stdout_pipe ();
            stdin_stream = process.get_stdin_pipe ();

            reader_thread = new Thread<void> ("lsp-reader", () => {
                read_loop ();
            });

            SourceFunc cont = start_server.callback;
            var init_params = build_init_params (workspace_root, initialization_options);

            new Thread<void> ("lsp-init", () => {
                var json = build_request_json ("initialize", init_params);
                send_message_sync (json);

                var initialized_json = build_notification_json ("initialized");
                send_message_sync (initialized_json);

                server_initialized = true;
                Idle.add ((owned) cont);
            });

            yield;

            initialized ();
            return true;
        } catch (Error e) {
            error_occurred ("Failed to start LSP server: %s".printf (e.message));
            return false;
        }
    }

    private void send_message_sync (string message) {
        if (stdin_stream == null) {
            return;
        }

        try {
            var full_message = "Content-Length: %d\r\n\r\n%s".printf (message.length, message);
            var data = full_message.data;
            stdin_stream.write (data);
            stdin_stream.flush ();
        } catch (Error e) {
            warning ("LSP sync write error: %s", e.message);
        }
    }

    private Json.Node build_init_params (string? workspace_root, Json.Node? initialization_options = null) {
        var builder = new Json.Builder ();
        builder.begin_object ();
        builder.set_member_name ("processId");
        builder.add_null_value ();
        builder.set_member_name ("clientInfo");
        builder.begin_object ();
        builder.set_member_name ("name");
        builder.add_string_value ("iide");
        builder.set_member_name ("version");
        builder.add_string_value ("0.1.0");
        builder.end_object ();
        builder.set_member_name ("rootUri");
        if (workspace_root != null) {
            builder.add_string_value (workspace_root);
        } else {
            builder.add_null_value ();
        }
        builder.set_member_name ("workspaceFolders");
        builder.begin_array ();
        if (workspace_root != null) {
            builder.begin_object ();
            builder.set_member_name ("uri");
            builder.add_string_value (workspace_root);
            builder.set_member_name ("name");
            builder.add_string_value ("workspace");
            builder.end_object ();
        }
        builder.end_array ();
        builder.set_member_name ("capabilities");
        builder.begin_object ();
        builder.set_member_name ("textDocument");
        builder.begin_object ();
        builder.set_member_name ("syncKind");
        builder.add_int_value (1);
        builder.end_object ();
        builder.end_object ();
        builder.set_member_name ("workspace");
        builder.begin_object ();
        builder.set_member_name ("workspaceFolders");
        builder.add_boolean_value (true);
        builder.end_object ();
        builder.end_object ();
        if (initialization_options != null) {
            builder.set_member_name ("initializationOptions");
            builder.add_value (initialization_options.copy ());
        }
        builder.end_object ();

        return builder.get_root ();
    }

    private async string ? send_request (string method, Json.Node? params) {
        int id = (int) next_request_id++;

        var builder = new Json.Builder ();
        builder.begin_object ();
        builder.set_member_name ("jsonrpc");
        builder.add_string_value ("2.0");
        builder.set_member_name ("id");
        builder.add_int_value (id);
        builder.set_member_name ("method");
        builder.add_string_value (method);
        builder.set_member_name ("params");
        if (params != null) {
            builder.add_value (params);
        } else {
            builder.begin_object ();
            builder.end_object ();
        }
        builder.end_object ();

        var generator = new Json.Generator ();
        generator.root = builder.get_root ();
        string json = generator.to_data (null);

        yield send_message (json);

        // Use GLib.Idle to frequently check for response without blocking
        return yield wait_for_response (id);
    }

    private async string ? wait_for_response (int id) {
        var source = new TimeoutSource (5000);
        source.set_callback (() => {
            wait_for_response.callback ();
            return Source.REMOVE;
        });
        source.attach (MainContext.get_thread_default ());

        // Check periodically until we get response or timeout
        while (true) {
            if (pending_responses.has_key (id)) {
                var result = pending_responses.get (id);
                pending_responses.unset (id);
                return result;
            }

            // Brief yield to allow event processing
            yield sleep (50);

            // Check again after yield
            if (pending_responses.has_key (id)) {
                var result = pending_responses.get (id);
                pending_responses.unset (id);
                return result;
            }
        }
    }

    private async void send_notification (string method, Json.Node? params) {
        var builder = new Json.Builder ();
        builder.begin_object ();
        builder.set_member_name ("jsonrpc");
        builder.add_string_value ("2.0");
        builder.set_member_name ("method");
        builder.add_string_value (method);
        builder.set_member_name ("params");
        if (params != null) {
            builder.add_value (params);
        } else {
            builder.begin_object ();
            builder.end_object ();
        }
        builder.end_object ();

        var generator = new Json.Generator ();
        generator.root = builder.get_root ();
        string json = generator.to_data (null);

        yield send_message (json);
    }

    public async IdeLspCompletionResult ? request_completion (string uri, int line, int character, string? trigger_character = null) {
        int id = (int) next_request_id; // Сохраняем текущий ID

        // Формируем параметры по спецификации LSP
        var builder = new Json.Builder ();
        builder.begin_object ();
        builder.set_member_name ("textDocument");
        builder.begin_object ();
        builder.set_member_name ("uri");
        builder.add_string_value (uri);
        builder.end_object ();

        builder.set_member_name ("position");
        builder.begin_object ();
        builder.set_member_name ("line");
        builder.add_int_value (line);
        builder.set_member_name ("character");
        builder.add_int_value (character);
        builder.end_object ();

        builder.end_object ();

        var json = build_request_json ("textDocument/completion", builder.get_root ());

        // Сохраняем callback текущей асинхронной функции
        pending_callbacks.set (id, new CallbackWrapper (request_completion.callback));

        // Отправляем сообщение
        send_message_sync (json);

        // ПРИОСТАНАВЛИВАЕМ выполнение до вызова callback в handle_incoming_message
        yield;

        // Когда выполнение возобновилось, забираем данные
        var response = response_data.get (id);
        response_data.unset (id);

        if (response == null || !response.has_member ("result"))return null;

        return parse_completion_result (response.get_member ("result"));
    }

    private IdeLspCompletionResult ? parse_completion_result (Json.Node node) {
        var result = new IdeLspCompletionResult ();
        result.items = new Gee.ArrayList<IdeLspCompletionItem> ();

        Json.Array items_array = null;

        // 1. LSP может вернуть либо массив, либо объект CompletionList
        if (node.get_node_type () == Json.NodeType.ARRAY) {
            items_array = node.get_array ();
        } else if (node.get_node_type () == Json.NodeType.OBJECT) {
            var obj = node.get_object ();
            if (obj.has_member ("items")) {
                items_array = obj.get_array_member ("items");
            }
            if (obj.has_member ("isIncomplete")) {
                result.is_incomplete = obj.get_boolean_member ("isIncomplete");
            }
        }

        if (items_array == null)return result;

        // 2. Итерируемся по элементам
        items_array.foreach_element ((array, index, item_node) => {
            var item_obj = item_node.get_object ();
            var item = new IdeLspCompletionItem ();

            item.label = item_obj.get_string_member ("label");

            if (item_obj.has_member ("detail"))
                item.detail = item_obj.get_string_member ("detail");

            if (item_obj.has_member ("insertText"))
                item.insert_text = item_obj.get_string_member ("insertText");
            else
                item.insert_text = item.label;

            if (item_obj.has_member ("kind"))
                item.kind = (IdeLspCompletionKind) item_obj.get_int_member ("kind");

            // Обработка документации (может быть строкой или объектом MarkupContent)
            if (item_obj.has_member ("documentation")) {
                item.documentation = item_obj.get_string_member ("documentation");
            }

            result.items.add (item);
        });

        return result;
    }

    private async void send_message (string message) {
        if (stdin_stream == null) {
            return;
        }

        if (is_writing) {
            message_queue.add (message);
            return;
        }

        is_writing = true;

        try {
            var full_message = "Content-Length: %d\r\n\r\n%s".printf (message.length, message);
            var data = full_message.data;
            size_t bytes_written = 0;
            yield stdin_stream.write_all_async (data, Priority.DEFAULT, null, out bytes_written);

            yield stdin_stream.flush_async (Priority.DEFAULT, null);
        } catch (Error e) {
            warning ("LSP Write error: %s", e.message);
            error_occurred ("Write error: %s".printf (e.message));
            is_writing = false;
            return;
        }

        while (message_queue.size > 0) {
            if (is_writing_queue) {
                break;
            }
            is_writing_queue = true;
            var queued = message_queue.get (0);
            message_queue.remove_at (0);
            try {
                var full_message = "Content-Length: %d\r\n\r\n%s".printf (queued.length, queued);
                var data = full_message.data;
                size_t bytes_written = 0;
                yield stdin_stream.write_all_async (data, Priority.DEFAULT, null, out bytes_written);

                yield stdin_stream.flush_async (Priority.DEFAULT, null);
            } catch (Error e) {
                warning ("LSP queued write error: %s", e.message);
                is_writing_queue = false;
                break;
            }
            is_writing_queue = false;
        }
        is_writing = false;
    }

    private bool shutting_down = false;

    private void read_loop () {
        var data_stream = new DataInputStream (stdout_stream);
        // Важно: LSP использует CRLF (\r\n)
        data_stream.set_newline_type (DataStreamNewlineType.CR_LF);

        try {
            while (true) {
                size_t content_length = 0;

                // 1. Читаем заголовки до пустой строки
                string line;
                while ((line = data_stream.read_line (null)) != null && line != "") {
                    if (line.has_prefix ("Content-Length:")) {
                        content_length = (size_t) uint64.parse (line.replace ("Content-Length:", "").strip ());
                    }
                }

                if (content_length == 0)continue;

                // 2. Читаем ровно content_length байт тела сообщения
                uint8[] buffer = new uint8[content_length];
                size_t bytes_read;
                data_stream.read_all (buffer, out bytes_read);

                if (bytes_read > 0) {
                    string json_data = (string) buffer;
                    json_data = json_data.substring (0, (int) bytes_read);

                    // Передаем обработку в основной поток (Main Loop)
                    Idle.add (() => {
                        handle_incoming_message (json_data);
                        return false;
                    });
                }
            }
        } catch (Error e) {
            warning ("LSP Read Error: %s", e.message);
        }
    }

    private void handle_incoming_message (string json_data) {
        try {
            var parser = new Json.Parser ();
            parser.load_from_data (json_data);
            var root = parser.get_root ().get_object ();

            // Вариант А: Это ответ на наш запрос (есть 'id')
            if (root.has_member ("id")) {
                int id = (int) root.get_int_member ("id");
                handle_response (id, root);
            }
            // Вариант Б: Это уведомление (есть 'method')
            else if (root.has_member ("method")) {
                string method = root.get_string_member ("method");
                handle_notification (method, root);
            }
        } catch (Error e) {
            print ("Failed to parse LSP JSON: %s", e.message);
        }
    }

    private void handle_response (int id, Json.Object root) {
        if (pending_callbacks.has_key (id)) {
            // Сохраняем результат, чтобы request_completion мог его прочитать
            response_data.set (id, root);

            var wrapper = pending_callbacks.get (id);
            if (wrapper != null) {
                pending_callbacks.unset (id);
                Idle.add ((owned) wrapper.callback);
            }
        }
    }

    private void handle_notification (string method, Json.Object root) {
        switch (method) {
        case "textDocument/publishDiagnostics" :
            handle_publish_diagnostics (root);
            break;
        case "$/progress" :
            break;
        case "window/showMessage" :
            break;
        }
    }

    private void handle_publish_diagnostics (Json.Object root) {
        var params = root.get_object_member ("params");
        var uri = params.get_string_member ("uri");
        var diag_list = params.get_array_member ("diagnostics");

        var diagnostics = new Gee.ArrayList<IdeLspDiagnostic> ();
        diag_list.foreach_element ((array, index, node) => {
            var obj = node.get_object ();
            var range = obj.get_object_member ("range");
            var start = range.get_object_member ("start");
            var end = range.get_object_member ("end");

            var d = new IdeLspDiagnostic ();
            d.message = obj.get_string_member ("message");
            d.severity = (int) obj.get_int_member ("severity");
            d.start_line = (int) start.get_int_member ("line");
            d.start_column = (int) start.get_int_member ("character");
            d.end_line = (int) end.get_int_member ("line");
            d.end_column = (int) end.get_int_member ("character");
            diagnostics.add (d);
        });

        diagnostics_received (uri, diagnostics);
    }

    public async void text_document_did_open (string uri, string language_id, int version, string content) {
        var builder = new Json.Builder ();
        builder.begin_object ();
        builder.set_member_name ("textDocument");
        builder.begin_object ();
        builder.set_member_name ("uri");
        builder.add_string_value (uri);
        builder.set_member_name ("languageId");
        builder.add_string_value (language_id);
        builder.set_member_name ("text");
        builder.add_string_value (content);
        builder.set_member_name ("version");
        builder.add_int_value (version);
        builder.end_object ();
        builder.end_object ();

        yield send_notification ("textDocument/didOpen", builder.get_root ());
    }

    public async void text_document_did_change (string uri, int version, string content, int? change_start, int? change_end) {
        var builder = new Json.Builder ();
        builder.begin_object ();
        builder.set_member_name ("textDocument");
        builder.begin_object ();
        builder.set_member_name ("uri");
        builder.add_string_value (uri);
        builder.set_member_name ("version");
        builder.add_int_value (version);
        builder.end_object ();

        builder.set_member_name ("contentChanges");
        builder.begin_array ();
        builder.begin_object ();
        builder.set_member_name ("text");
        builder.add_string_value (content);
        builder.end_object ();
        builder.end_array ();
        builder.end_object ();

        yield send_notification ("textDocument/didChange", builder.get_root ());
    }

    public async void text_document_did_close (string uri) {
        var builder = new Json.Builder ();
        builder.begin_object ();
        builder.set_member_name ("textDocument");
        builder.begin_object ();
        builder.set_member_name ("uri");
        builder.add_string_value (uri);
        builder.end_object ();
        builder.end_object ();

        yield send_notification ("textDocument/didClose", builder.get_root ());
    }

    private async bool sleep (uint ms) {
        var source = new TimeoutSource (ms);
        source.set_callback (() => {
            return Source.REMOVE;
        });
        source.attach (MainContext.get_thread_default ());
        return true;
    }

    public void shutdown () {
        shutting_down = true;
        if (process != null) {
            process.force_exit ();
        }
    }
}
