/*
 * LSPService.vala
 *
 * Copyright 2026 kai
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

using GLib;

public class Iide.LSPClient : GLib.Object {
    private static LSPClient? _instance;
    private SubprocessLauncher? launcher;
    private Subprocess? process;
    private IOConsumer? consumer;
    private GLib.OutputStream? stdin_stream;
    private uint next_request_id = 1;
    private Gee.ArrayList<string> message_queue;
    private int queue_head = 0;
    private bool is_writing = false;

    public signal void initialized ();
    public signal void diagnostics_received (string uri, Gee.ArrayList<Diagnostic> diagnostics);
    public signal void error_occurred (string message);

    public class Diagnostic : GLib.Object {
        public int severity { get; construct; default = 1; }
        public string message { get; construct; default = ""; }
        public int start_line { get; construct; default = 0; }
        public int start_column { get; construct; default = 0; }
        public int end_line { get; construct; default = 0; }
        public int end_column { get; construct; default = 0; }
    }

    public static unowned LSPClient get_instance () {
        if (_instance == null) {
            _instance = new LSPClient ();
        }
        return _instance;
    }

    public async bool start_server (string command, string[] args, string? workspace_root) {
        try {
            message_queue = new Gee.ArrayList<string> ();
            queue_head = 0;
            is_writing = false;

            var argv = new Gee.ArrayList<string> ();
            argv.add (command);
            foreach (var arg in args) {
                argv.add (arg);
            }

            launcher = new SubprocessLauncher (SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDIN_PIPE);
            process = launcher.spawnv (argv.to_array ());
            debug ("LSP: Started process %s", command);

            stdin_stream = process.get_stdin_pipe ();
            consumer = new IOConsumer (process.get_stdout_pipe ());
            consumer.message.connect (on_message_received);
            debug ("LSP: Connected stdout pipe");

            var init_params = build_init_params (workspace_root);
            var init_json = build_request ("initialize", init_params);
            debug ("LSP: Sending initialize request");
            yield send_message (init_json);
            debug ("LSP: initialize sent");

            var notif = build_notification ("initialized", null);
            debug ("LSP: Sending initialized notification");
            yield send_message (notif);
            debug ("LSP: initialized sent");

            initialized ();
            debug ("LSP: Server initialized successfully");
            return true;
        } catch (Error e) {
            error_occurred ("Failed to start LSP server: %s".printf (e.message));
            return false;
        }
    }

    private async bool send_message (string message) {
        if (stdin_stream == null) {
            warning ("LSP: stdin_stream is null");
            return false;
        }

        if (is_writing) {
            message_queue.add (message);
            debug ("LSP: Queued message (queue size: %d)", message_queue.size);
            return true;
        }

        is_writing = true;
        bool result = yield do_write_message (message);

        while (queue_head < message_queue.size) {
            var next = message_queue.get (queue_head);
            queue_head++;
            if (next != null) {
                yield do_write_message (next);
            }
        }

        message_queue.clear ();
        queue_head = 0;
        is_writing = false;
        return result;
    }

    private async bool do_write_message (string message) {
        try {
            var data = message.data;
            var length = data.length;
            var header = "Content-Length: %d\r\n\r\n".printf (length);
            string full_message = header + message;

            uint8[] buffer = new uint8[full_message.length];
            for (int i = 0; i < full_message.length; i++) {
                buffer[i] = (uint8) full_message[i];
            }

            size_t bytes_written = 0;
            yield stdin_stream.write_all_async (buffer, GLib.Priority.DEFAULT, null, out bytes_written);
            yield stdin_stream.flush_async (GLib.Priority.DEFAULT, null);
            return true;
        } catch (Error e) {
            warning ("LSP Write error: %s", e.message);
            error_occurred ("Write error: %s".printf (e.message));
            return false;
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
        builder.set_member_name ("completion");
        builder.begin_object ();
        builder.set_member_name ("dynamicRegistration");
        builder.add_boolean_value (false);
        builder.end_object ();
        builder.end_object ();
        builder.set_member_name ("definition");
        builder.begin_object ();
        builder.set_member_name ("dynamicRegistration");
        builder.add_boolean_value (false);
        builder.end_object ();
        builder.end_object ();
        builder.set_member_name ("workspace");
        builder.begin_object ();
        builder.set_member_name ("workspaceFolders");
        builder.begin_array ();
        builder.begin_object ();
        builder.set_member_name ("uri");
        builder.add_string_value (workspace_root != null ? workspace_root : "file://");
        builder.set_member_name ("name");
        builder.add_string_value ("workspace");
        builder.end_object ();
        builder.end_array ();
        builder.end_object ();
        builder.end_object ();

        return builder.get_root ();
    }

    private string build_request (string method, Json.Node params) {
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
        builder.add_value (params);
        builder.end_object ();

        var generator = new Json.Generator ();
        generator.root = builder.get_root ();
        return generator.to_data (null);
    }

    private string build_notification (string method, Json.Node? params) {
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

    private void on_message_received (GLib.Bytes data) {
        uint8[] raw_data = data.get_data ();
        
        if (raw_data.length > 0 && raw_data[0] == 0xEF && raw_data.length > 2 && 
            raw_data[1] == 0xBB && raw_data[2] == 0xBF) {
            uint8[] new_data = new uint8[raw_data.length - 3];
            for (int i = 0; i < new_data.length; i++) {
                new_data[i] = raw_data[i + 3];
            }
            raw_data = new_data;
        }
        
        for (int i = 0; i < raw_data.length; i++) {
            if (raw_data[i] == '\n' || raw_data[i] == '\r') {
                raw_data[i] = ' ';
            }
        }
        
        var parser = new Json.Parser ();
        try {
            parser.load_from_data ((string) raw_data);
            var reader = new Json.Reader (parser.get_root ());

            reader.read_member ("jsonrpc");
            string jsonrpc = reader.get_string_value ();
            reader.end_member ();
            if (jsonrpc != "2.0") {
                return;
            }

            if (reader.read_member ("method")) {
                string method = reader.get_string_value ();
                reader.end_member ();

                if (reader.read_member ("params")) {
                    handle_notification (reader, method);
                    reader.end_member ();
                }
            } else {
                reader.end_member ();
                if (reader.read_member ("id")) {
                    reader.end_member ();
                }
            }
        } catch (Error e) {
        }
    }

    private void handle_notification (Json.Reader reader, string method) {
        switch (method) {
            case "textDocument/publishDiagnostics":
                handle_publish_diagnostics (reader);
                break;
            case "window/showMessage":
                handle_show_message (reader);
                break;
        }
    }

    private void handle_publish_diagnostics (Json.Reader reader) {
        try {
            if (!reader.read_member ("uri")) {
                return;
            }
            string uri = reader.get_string_value ();
            reader.end_member ();

            if (!reader.read_member ("diagnostics")) {
                reader.end_member ();
                return;
            }

            var diagnostics = new Gee.ArrayList<Diagnostic> ();

            if (reader.is_array ()) {
                int count = (int) reader.count_elements ();
                for (int i = 0; i < count; i++) {
                    reader.read_element (i);
                    var diag = parse_diagnostic (reader);
                    diagnostics.add (diag);
                    reader.end_element ();
                }
            }
            reader.end_member ();

            diagnostics_received (uri, diagnostics);
        } catch (Error e) {
        }
    }

    private Diagnostic parse_diagnostic (Json.Reader reader) throws Error {
        int severity = 1;
        string diag_message = "";
        int start_line = 0, start_col = 0, end_line = 0, end_col = 0;

        if (reader.read_member ("severity")) {
            severity = (int) reader.get_int_value ();
            reader.end_member ();
        }

        if (reader.read_member ("message")) {
            diag_message = reader.get_string_value ();
            reader.end_member ();
        }

        if (reader.read_member ("range")) {
            reader.read_member ("start");
            reader.read_member ("line");
            start_line = (int) reader.get_int_value ();
            reader.end_member ();
            reader.read_member ("character");
            start_col = (int) reader.get_int_value ();
            reader.end_member ();
            reader.end_member ();

            reader.read_member ("end");
            reader.read_member ("line");
            end_line = (int) reader.get_int_value ();
            reader.end_member ();
            reader.read_member ("character");
            end_col = (int) reader.get_int_value ();
            reader.end_member ();
            reader.end_member ();
            reader.end_member ();
        }

        return (Diagnostic) Object.new (
            typeof (Diagnostic),
            "severity", severity,
            "message", diag_message,
            "start_line", start_line,
            "start_column", start_col,
            "end_line", end_line,
            "end_column", end_col
        );
    }

    private void handle_show_message (Json.Reader reader) {
        try {
            reader.read_member ("type");
            int type = (int) reader.get_int_value ();
            reader.end_member ();

            reader.read_member ("message");
            string message = reader.get_string_value ();
            reader.end_member ();

            debug ("[LSP %d] %s", type, message);
        } catch (Error e) {
        }
    }

    public void text_document_did_open (string uri, string language_id, int version, string text) {
        debug ("LSP: Sending didOpen for %s (lang=%s)", uri, language_id);
        var builder = new Json.Builder ();
        builder.begin_object ();
        builder.set_member_name ("textDocument");
        builder.begin_object ();
        builder.set_member_name ("uri");
        builder.add_string_value (uri);
        builder.set_member_name ("languageId");
        builder.add_string_value (language_id);
        builder.set_member_name ("version");
        builder.add_int_value (version);
        builder.set_member_name ("text");
        builder.add_string_value (text);
        builder.end_object ();
        builder.end_object ();

        var notif = build_notification ("textDocument/didOpen", builder.get_root ());
        send_message.begin (notif);
        debug ("LSP: didOpen sent");
    }

    public void text_document_did_change (string uri, int version, string text) {
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
        builder.add_string_value (text);
        builder.end_object ();
        builder.end_array ();
        builder.end_object ();

        var notif = build_notification ("textDocument/didChange", builder.get_root ());
        send_message.begin (notif);
    }

    public void stop () {
        if (process != null) {
            process.force_exit ();
            process = null;
        }
    }
}

public class Iide.IOConsumer : GLib.Object {
    private GLib.InputStream stream;
    private uint8[] chunk_buffer = new uint8[65536];
    private int chunk_used = 0;

    public signal void message (GLib.Bytes data);

    public IOConsumer (GLib.InputStream stream) {
        if (stream == null) {
            warning ("IOConsumer: stream is NULL");
            return;
        }
        this.stream = stream;
        new Thread<void> ("lsp-reader", () => {
            read_thread ();
        });
    }

    private void read_thread () {
        uint8[] buffer = new uint8[65536];
        while (true) {
            try {
                size_t bytes_read = stream.read (buffer);
                if (bytes_read == 0) {
                    break;
                }
                
                bool at_line_start = true;
                
                for (size_t i = 0; i < bytes_read; i++) {
                    uint8 byte = buffer[i];
                    bool is_newline = (byte == '\n');
                    
                    if (at_line_start) {
                        if (byte == 'I' || byte == 'E' || byte == 'W' || byte == '<') {
                            while (i < bytes_read && buffer[i] != '\n') {
                                i++;
                            }
                            at_line_start = true;
                            continue;
                        }
                    }
                    
                    chunk_buffer[chunk_used++] = byte;
                    if (chunk_used >= chunk_buffer.length) {
                        warning ("IOConsumer: buffer overflow, resetting");
                        chunk_used = 0;
                    }
                    at_line_start = is_newline;
                }
                process_buffer ();
            } catch (Error e) {
                warning ("IOConsumer: Thread error: %s", e.message);
                break;
            }
        }
    }

    private void process_buffer () {
        while (chunk_used > 0) {
            int header_end = -1;
            int body_start = -1;
            int content_length = -1;
            
            for (int i = 0; i < chunk_used - 3; i++) {
                if (chunk_buffer[i] == '\r' && chunk_buffer[i+1] == '\n' &&
                    chunk_buffer[i+2] == '\r' && chunk_buffer[i+3] == '\n') {
                    header_end = i;
                    body_start = i + 4;
                    break;
                }
            }
            
            if (header_end == -1) {
                if (chunk_used > 4000) {
                    warning ("IOConsumer: no header in %d bytes", chunk_used);
                    chunk_used = 0;
                }
                return;
            }
            
            string header = ((string) chunk_buffer[0:header_end]);
            string[] lines = header.split ("\r\n");
            foreach (var line in lines) {
                if (line.has_prefix ("Content-Length: ")) {
                    content_length = int.parse (line.substring (15));
                }
            }

            if (content_length <= 0) {
                warning ("IOConsumer: no Content-Length");
                chunk_used = 0;
                return;
            }

            if (chunk_used < body_start + content_length) {
                return;
            }
            
            uint8[] body = new uint8[content_length];
            for (int i = 0; i < content_length; i++) {
                body[i] = chunk_buffer[body_start + i];
            }

            int remaining = chunk_used - (body_start + content_length);
            for (int i = 0; i < remaining; i++) {
                chunk_buffer[i] = chunk_buffer[body_start + content_length + i];
            }
            chunk_used = remaining;

            message (new GLib.Bytes (body));
        }
    }
}
