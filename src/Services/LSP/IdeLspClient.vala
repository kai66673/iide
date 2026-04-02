using GLib;
using Json;

namespace Iide {

public class IdeLspDiagnostic : GLib.Object {
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

public class IdeLspClient : GLib.Object {
    public signal void initialized ();
    public signal void diagnostics_received (string uri, Gee.ArrayList<IdeLspDiagnostic> diagnostics);
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
    private size_t buffer_used = 0;
    private Thread<void>? reader_thread;

    private bool is_writing = false;
    private bool is_writing_queue = false;
    private Gee.ArrayList<string> message_queue;

    public IdeLspClient () {
        pending_requests = new Gee.HashMap<int, Cancellable?> ();
        message_queue = new Gee.ArrayList<string> ();
        read_buffer = new uint8[65536];
    }

    public async bool start_server (string command, string[] args, string? workspace_root) {
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
            var init_params = build_init_params (workspace_root);
            
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

    private string build_request_json (string method, Json.Node? params) {
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

    private Json.Node build_init_params (string? workspace_root) {
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
        builder.set_member_name ("capabilities");
        builder.begin_object ();

        builder.set_member_name ("textDocument");
        builder.begin_object ();
        builder.set_member_name ("syncKind");
        builder.begin_object ();
        builder.set_member_name ("textDocumentSync");
        builder.add_int_value (1);
        builder.end_object ();
        builder.end_object ();
        builder.end_object ();

        builder.set_member_name ("workspace");
        builder.begin_object ();
        builder.set_member_name ("workspaceFolders");
        builder.add_boolean_value (true);
        builder.end_object ();
        builder.end_object ();

        return builder.get_root ();
    }

    private async Variant? send_request (string method, Json.Node? params) {
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

        var cancellable = new Cancellable ();
        pending_requests.set (id, cancellable);

        yield send_message (json);

        yield sleep (500);

        pending_requests.unset (id);
        return null;
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
    private bool reader_started = false;

    private void read_loop () {
        if (stdout_stream == null) {
            warning ("LSP: stdout_stream is null in read_loop");
            return;
        }

        reader_started = true;
        uint8[] buffer = new uint8[65536];
        while (!shutting_down) {
            try {
                size_t bytes_read = stdout_stream.read (buffer);
                if (bytes_read == 0) {
                    if (!shutting_down) {
                        warning ("LSP: stdout read returned 0, process may have exited");
                    }
                    break;
                }

                if (buffer_used + bytes_read > read_buffer.length) {
                    buffer_used = 0;
                }

                for (size_t i = 0; i < bytes_read; i++) {
                    read_buffer[buffer_used++] = buffer[i];
                }

                process_read_buffer ();
            } catch (Error e) {
                if (!shutting_down) {
                    warning ("LSP read error: %s", e.message);
                }
                break;
            }
        }
        reader_started = false;
    }

    private void process_read_buffer () {
        while (buffer_used > 0) {
            int header_end = -1;
            int body_start = -1;
            int content_length = -1;

            for (int i = 0; i < buffer_used - 3; i++) {
                if (read_buffer[i] == '\r' && read_buffer[i + 1] == '\n' &&
                    read_buffer[i + 2] == '\r' && read_buffer[i + 3] == '\n') {
                    header_end = i;
                    body_start = i + 4;
                    break;
                }
            }

            if (header_end == -1) {
                if (buffer_used > 4096) {
                    warning ("LSP: no header found in %lu bytes", buffer_used);
                    buffer_used = 0;
                }
                return;
            }

            var header_slice = (string) read_buffer[0:header_end];
            string header = (!) header_slice;
            string[] lines = header.split ("\r\n");
            foreach (var line in lines) {
                if (line.has_prefix ("Content-Length: ")) {
                    content_length = int.parse (line.substring (15));
                }
            }

            if (content_length <= 0) {
                warning ("LSP: no Content-Length");
                buffer_used = 0;
                return;
            }

            if (buffer_used < body_start + content_length) {
                return;
            }

            var body_bytes = new uint8[content_length + 1];
            for (int i = 0; i < content_length; i++) {
                body_bytes[i] = read_buffer[body_start + i];
            }
            body_bytes[content_length] = 0;
            string body = (string) body_bytes;

            var remaining = buffer_used - (body_start + content_length);
            if (remaining > 0) {
                for (size_t i = 0; i < remaining; i++) {
                    read_buffer[i] = read_buffer[body_start + content_length + i];
                }
            }
            buffer_used = remaining;

            handle_message (body);
        }
    }

    private void handle_message (string body) {
        var parser = new Json.Parser ();
        try {
            parser.load_from_data (body);
        } catch (Error e) {
            warning ("LSP JSON parse error: %s", e.message);
            return;
        }

        var root = parser.get_root ();
        var obj = root.get_object ();

        if (obj.has_member ("method")) {
            string method = obj.get_string_member ("method");
            if (obj.has_member ("params")) {
                handle_notification (method, obj.get_member ("params"));
            }
        }
    }

    private void handle_notification (string method, Json.Node params) {
        if (method == "textDocument/publishDiagnostics") {
            handle_publish_diagnostics (params);
        } else if (method == "$/progress") {
        } else if (method == "window/showMessage") {
        }
    }

    private void handle_publish_diagnostics (Json.Node params) {
        if (params.get_node_type () != Json.NodeType.OBJECT) {
            return;
        }
        
        var obj = params.get_object ();

        string uri = "";
        if (obj.has_member ("uri")) {
            uri = obj.get_string_member ("uri");
        }

        var diagnostics = new Gee.ArrayList<IdeLspDiagnostic> ();

        if (obj.has_member ("diagnostics") && obj.get_member ("diagnostics").get_node_type () == Json.NodeType.ARRAY) {
            var diag_array_node = obj.get_member ("diagnostics");
            var diag_array = diag_array_node.get_array ();
            for (int i = 0; i < (int) diag_array.get_length (); i++) {
                var diag_node = diag_array.get_element (i);
                if (diag_node.get_node_type () != Json.NodeType.OBJECT) {
                    continue;
                }
                
                var diag_obj = diag_node.get_object ();
                var diag = new IdeLspDiagnostic ();

                if (diag_obj.has_member ("severity")) {
                    diag.severity = (int) diag_obj.get_member ("severity").get_int ();
                }
                if (diag_obj.has_member ("message")) {
                    diag.message = diag_obj.get_string_member ("message");
                }

                if (diag_obj.has_member ("range") && diag_obj.get_member ("range").get_node_type () == Json.NodeType.OBJECT) {
                    var range = diag_obj.get_member ("range").get_object ();
                    if (range.has_member ("start") && range.get_member ("start").get_node_type () == Json.NodeType.OBJECT) {
                        var start = range.get_member ("start").get_object ();
                        if (start.has_member ("line")) {
                            diag.start_line = (int) start.get_member ("line").get_int ();
                        }
                        if (start.has_member ("character")) {
                            diag.start_column = (int) start.get_member ("character").get_int ();
                        }
                    }
                    if (range.has_member ("end") && range.get_member ("end").get_node_type () == Json.NodeType.OBJECT) {
                        var end = range.get_member ("end").get_object ();
                        if (end.has_member ("line")) {
                            diag.end_line = (int) end.get_member ("line").get_int ();
                        }
                        if (end.has_member ("character")) {
                            diag.end_column = (int) end.get_member ("character").get_int ();
                        }
                    }
                }

                diagnostics.add (diag);
            }
        }

        debug ("IdeLspClient: Emitting diagnostics_received for %s with %d items", uri, diagnostics.size);
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

}