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
            var argv = new Gee.ArrayList<string> ();
            argv.add (command);
            foreach (var arg in args) {
                argv.add (arg);
            }

            launcher = new SubprocessLauncher (SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDIN_PIPE);
            process = launcher.spawnv (argv.to_array ());

            stdin_stream = process.get_stdin_pipe ();
            consumer = new IOConsumer (process.get_stdout_pipe ());
            consumer.message.connect (on_message_received);

            var init_params = build_init_params (workspace_root);
            var init_json = build_request ("initialize", init_params);
            yield send_message (init_json);

            var notif = build_notification ("initialized", null);
            yield send_message (notif);

            initialized ();
            return true;
        } catch (Error e) {
            error_occurred ("Failed to start LSP server: %s".printf (e.message));
            return false;
        }
    }

    private async bool send_message (string message) {
        if (stdin_stream == null) return false;

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
        string response = (string) data.get_data ();

        var parser = new Json.Parser ();
        try {
            parser.load_from_data (response);
            var reader = new Json.Reader (parser.get_root ());

            reader.read_member ("jsonrpc");
            string jsonrpc = reader.get_string_value ();
            reader.end_member ();
            if (jsonrpc != "2.0") return;

            if (reader.read_member ("method")) {
                string method = reader.get_string_value ();
                reader.end_member ();

                reader.read_member ("params");
                handle_notification (reader, method);
                reader.end_member ();
            } else {
                reader.end_member ();
                if (reader.read_member ("id")) {
                    reader.end_member ();
                }
            }
        } catch (Error e) {
            error_occurred ("Parse error: %s".printf (e.message));
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
            reader.read_member ("uri");
            string uri = reader.get_string_value ();
            reader.end_member ();

            reader.read_member ("diagnostics");
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
        string message = "";
        int start_line = 0, start_col = 0, end_line = 0, end_col = 0;

        if (reader.read_member ("severity")) {
            severity = (int) reader.get_int_value ();
            reader.end_member ();
        }

        if (reader.read_member ("message")) {
            message = reader.get_string_value ();
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
            "message", message,
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
    private int content_length = -1;
    private uint8[] chunk_buffer = new uint8[65536];
    private int chunk_used = 0;

    public signal void message (GLib.Bytes data);

    public IOConsumer (GLib.InputStream stream) {
        this.stream = stream;
        read_chunk ();
    }

    private async void read_chunk () {
        try {
            uint8[] buffer = new uint8[65536];
            size_t bytes_read = 0;
            bool success = yield stream.read_all_async (buffer, 65536, null, out bytes_read);
            if (!success || bytes_read == 0) {
                return;
            }

            int available = chunk_used + (int) bytes_read;
            if (available > chunk_buffer.length) {
                available = chunk_buffer.length - chunk_used;
                if ((int) bytes_read < available) {
                    available = (int) bytes_read;
                }
            }
            
            for (size_t i = 0; i < bytes_read && chunk_used < chunk_buffer.length; i++) {
                chunk_buffer[chunk_used++] = buffer[i];
            }

            process_buffer ();
            read_chunk ();
        } catch (Error e) {
        }
    }

    private void process_buffer () {
        int header_end = -1;
        for (int i = 0; i < chunk_used - 3; i++) {
            if (chunk_buffer[i] == '\r' && chunk_buffer[i+1] == '\n' &&
                chunk_buffer[i+2] == '\n') {
                header_end = i;
                break;
            }
        }
        
        if (header_end == -1 && chunk_used >= 4) {
            for (int i = 0; i < chunk_used - 4; i++) {
                if (chunk_buffer[i] == '\r' && chunk_buffer[i+1] == '\n' &&
                    chunk_buffer[i+2] == '\r' && chunk_buffer[i+3] == '\n') {
                    header_end = i;
                    break;
                }
            }
        }
        
        if (header_end == -1) return;

        string header = (string) chunk_buffer[0:header_end];
        int body_start = header_end + (chunk_buffer[header_end + 1] == '\n' ? 4 : 4);

        string[] lines = header.split ("\r\n");
        foreach (var line in lines) {
            if (line.has_prefix ("Content-Length: ")) {
                string len_str = line.substring (15);
                content_length = int.parse (len_str);
            }
        }

        if (content_length == -1) return;

        int body_length = chunk_used - body_start;
        if (body_length >= content_length) {
            uint8[] body = new uint8[content_length];
            for (int i = 0; i < content_length; i++) {
                body[i] = chunk_buffer[body_start + i];
            }

            int remaining = chunk_used - (body_start + content_length);
            for (int i = 0; i < remaining; i++) {
                chunk_buffer[i] = chunk_buffer[body_start + content_length + i];
            }
            chunk_used = remaining;

            content_length = -1;
            message (new GLib.Bytes (body));

            if (chunk_used > 0) {
                process_buffer ();
            }
        }
    }
}
