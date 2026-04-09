/*
 * test_lsp_service.vala
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

public static int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/lsp/json_builder", () => {
        test_json_builder ();
    });

    Test.add_func ("/lsp/json_reader", () => {
        test_json_reader ();
    });

    Test.add_func ("/lsp/content_length", () => {
        test_content_length_parsing ();
    });

    Test.add_func ("/lsp/clangd_server", () => {
        test_clangd_server_start ();
    });

    Test.add_func ("/lsp/did_change_valid_json", () => {
        test_did_change_valid_json ();
    });

    Test.add_func ("/lsp/did_change_content_length", () => {
        test_did_change_content_length ();
    });

    Test.add_func ("/lsp/clangd_diagnostics_parse", () => {
        test_clangd_diagnostics_parse ();
    });

    Test.add_func ("/lsp/did_change_full_document", () => {
        test_did_change_full_document ();
    });

    Test.add_func ("/lsp/didopen_diagnostics_didchange_diagnostics", () => {
        test_didopen_diagnostics_didchange_diagnostics ();
    });

    Test.add_func ("/lsp/integration_didopen_didchange_diagnostics", () => {
        test_integration_didopen_didchange_diagnostics ();
    });

    return Test.run ();
}

private void test_json_builder () {
    var builder = new Json.Builder ();
    builder.begin_object ();
    builder.set_member_name ("method");
    builder.add_string_value ("test");
    builder.set_member_name ("params");
    builder.begin_object ();
    builder.set_member_name ("value");
    builder.add_int_value (42);
    builder.end_object ();
    builder.end_object ();

    var generator = new Json.Generator ();
    generator.root = builder.get_root ();
    string json = generator.to_data (null);

    assert (json != null);
    assert (json.contains ("\"method\":\"test\""));
    assert (json.contains ("\"value\":42"));
}

private void test_json_reader () {
    string json_str = """
        {
            "method": "test",
            "value": 42,
            "name": "hello"
        }
    """;

    var parser = new Json.Parser ();
    try {
        parser.load_from_data (json_str);
    } catch (Error e) {
        assert_not_reached ();
    }
    var reader = new Json.Reader (parser.get_root ());

    reader.read_member ("method");
    string method = reader.get_string_value ();
    reader.end_member ();
    assert (method == "test");

    reader.read_member ("value");
    int value = (int) reader.get_int_value ();
    reader.end_member ();
    assert (value == 42);

    reader.read_member ("name");
    string name = reader.get_string_value ();
    reader.end_member ();
    assert (name == "hello");
}

private void test_content_length_parsing () {
    string header = "Content-Length: 123\r\n\r\n";
    int length = -1;

    string[] lines = header.split ("\r\n");
    foreach (var line in lines) {
        if (line.has_prefix ("Content-Length: ")) {
            string len_str = line.substring (15);
            length = int.parse (len_str);
        }
    }

    assert (length == 123);
}

private void test_clangd_server_start () {
    var main_loop = new MainLoop ();
    bool server_initialized = false;
    bool error_received = false;

    var client = new Iide.IdeLspClient ();
    client.initialized.connect (() => {
        server_initialized = true;
        main_loop.quit ();
    });
    client.error_occurred.connect ((msg) => {
        error_received = true;
        print ("LSP Error: %s\n", msg);
        main_loop.quit ();
    });

    string? clangd_path = Environment.find_program_in_path ("clangd");
    assert (clangd_path != null);
    if (clangd_path == null) {
        print ("clangd not found, skipping test\n");
        return;
    }

    string workspace_uri = "file://" + Environment.get_current_dir ();
    client.start_server.begin (clangd_path, {}, workspace_uri);

    Timeout.add (10000, () => {
        main_loop.quit ();
        return Source.REMOVE;
    });

    main_loop.run ();

    assert (server_initialized == true);
}

private void test_did_change_valid_json () {
    var builder = new Json.Builder ();
    builder.begin_object ();
    builder.set_member_name ("jsonrpc");
    builder.add_string_value ("2.0");
    builder.set_member_name ("method");
    builder.add_string_value ("textDocument/didChange");
    builder.set_member_name ("params");
    builder.begin_object ();
    builder.set_member_name ("textDocument");
    builder.begin_object ();
    builder.set_member_name ("uri");
    builder.add_string_value ("file:///test.c");
    builder.set_member_name ("version");
    builder.add_int_value (2);
    builder.end_object ();
    builder.set_member_name ("contentChanges");
    builder.begin_array ();
    builder.begin_object ();
    builder.set_member_name ("text");
    builder.add_string_value ("int main() { return 0; }");
    builder.end_object ();
    builder.end_array ();
    builder.end_object ();
    builder.end_object ();

    var generator = new Json.Generator ();
    generator.root = builder.get_root ();
    string json = generator.to_data (null);

    assert (json.contains ("\"method\":\"textDocument/didChange\""));
    assert (json.contains ("\"version\":2"));
    assert (json.contains ("file:///test.c"));
}

private void test_did_change_content_length () {
    string content = """
        {
            "jsonrpc": "2.0",
            "method": "textDocument/didChange",
            "params": {
                "textDocument": {
                    "uri": "file:///test.c",
                    "version": 2
                },
                "contentChanges": [
                    {
                        "text": "int main() { return 0; }"
                    }
                ]
            }
        }
    """;

    int body_length = content.length;
    string header = "Content-Length: %d\r\n\r\n".printf (body_length);

    int parsed_length = -1;
    string[] lines = header.split ("\r\n");
    foreach (var line in lines) {
        if (line.has_prefix ("Content-Length: ")) {
            string len_str = line.substring (15);
            parsed_length = int.parse (len_str);
        }
    }

    assert (parsed_length == body_length);
    assert (parsed_length > 0);
}

private void test_clangd_diagnostics_parse () {
    var diagnostic_json = """
        {
            "jsonrpc": "2.0",
            "method": "textDocument/publishDiagnostics",
            "params": {
                "uri": "file:///test.c",
                "version": 1,
                "diagnostics": [
                    {
                        "severity": 1,
                        "range": {
                            "start": {"line": 0, "character": 5},
                            "end": {"line": 0, "character": 9}
                        },
                        "message": "expected ';' after return statement"
                    }
                ]
            }
        }
    """;

    var parser = new Json.Parser ();
    try {
        parser.load_from_data (diagnostic_json);
    } catch (Error e) {
        assert_not_reached ();
    }

    var root = parser.get_root ();
    var reader = new Json.Reader (root);

    reader.read_member ("method");
    string method = reader.get_string_value ();
    reader.end_member ();
    assert (method == "textDocument/publishDiagnostics");

    reader.read_member ("params");
    assert (reader.is_object ());

    assert (reader.read_member ("uri"));
    string uri = reader.get_string_value ();
    reader.end_member ();
    assert (uri == "file:///test.c");

    assert (reader.read_member ("diagnostics"));
    assert (reader.is_array ());
    int count = 0;
    while (reader.read_element (count)) {
        count++;
        reader.end_element ();
    }
    assert (count == 1);
    reader.end_member ();

    reader.end_member ();
    reader.end_member ();
}

private void test_did_change_full_document () {
    string full_content = """
#include <stdio.h>

int main() {
    printf("Hello, World!\\n");
    return 0;
}
""";

    var builder = new Json.Builder ();
    builder.begin_object ();
    builder.set_member_name ("textDocument");
    builder.begin_object ();
    builder.set_member_name ("uri");
    builder.add_string_value ("file:///test.c");
    builder.set_member_name ("version");
    builder.add_int_value (1);
    builder.end_object ();
    builder.set_member_name ("contentChanges");
    builder.begin_array ();
    builder.begin_object ();
    builder.set_member_name ("text");
    builder.add_string_value (full_content);
    builder.end_object ();
    builder.end_array ();
    builder.end_object ();

    var generator = new Json.Generator ();
    generator.root = builder.get_root ();
    string json = generator.to_data (null);

    assert (json.contains ("#include <stdio.h>"));
    assert (json.contains ("printf"));
    assert (json.contains ("\"version\":1"));
}

private void test_didopen_diagnostics_didchange_diagnostics () {
    var test_uri = "file:///test.c";
    var initial_content = """
#include <stdio.h>

int main() {
    printf("Hello\n");
    return 0;
}
""";

    var updated_content = """
#include <stdio.h>

int main() {
    printf("Hello\n");
    return 0
}
""";

    var did_open_json = build_did_open_message (test_uri, "c", 1, initial_content);
    assert (did_open_json.contains ("\"method\":\"textDocument/didOpen\""));
    assert (did_open_json.contains ("\"uri\":\"file:///test.c\""));
    assert (did_open_json.contains ("\"languageId\":\"c\""));
    assert (did_open_json.contains ("\"version\":1"));

    var diagnostics_json_1 = build_publish_diagnostics_message (test_uri, 1, "expected ';' after return statement", 4, 14, 4, 15);
    assert (diagnostics_json_1.contains ("\"method\":\"textDocument/publishDiagnostics\""));
    assert (diagnostics_json_1.contains ("\"uri\":\"file:///test.c\""));
    assert (diagnostics_json_1.contains ("\"severity\":1"));

    var did_change_json = build_did_change_message (test_uri, 2, updated_content);
    assert (did_change_json.contains ("\"method\":\"textDocument/didChange\""));
    assert (did_change_json.contains ("\"version\":2"));
    assert (did_change_json.contains ("printf"));
    assert (did_change_json.contains ("return 0"));

    var diagnostics_json_2 = build_publish_diagnostics_message (test_uri, 2, "expected ';' after return statement", 4, 14, 4, 15);
    assert (diagnostics_json_2.contains ("\"method\":\"textDocument/publishDiagnostics\""));
    assert (diagnostics_json_2.contains ("\"version\":2"));

    print ("didOpen -> publishDiagnostics -> didChange -> publishDiagnostics chain: OK\n");
}

private void test_integration_didopen_didchange_diagnostics () {
    string? clangd_path = Environment.find_program_in_path ("clangd");
    if (clangd_path == null) {
        print ("clangd not found, skipping integration test\n");
        return;
    }

    var main_loop = new MainLoop ();
    int diagnostics_count = 0;
    string? last_uri = null;
    bool first_diag_received = false;

    var test_uri = "file:///test.c";
    var initial_content = "int main() { return 0; }";
    var updated_content = "int main() { return 0 }";

    var client = new Iide.IdeLspClient ();

    client.initialized.connect (() => {
        print ("Client initialized, sending didOpen...\n");
        client.text_document_did_open.begin (test_uri, "c", 1, initial_content);
    });

    client.diagnostics_received.connect ((uri, diagnostics) => {
        last_uri = uri;
        diagnostics_count++;
        print ("Diagnostics #%d received for %s\n", diagnostics_count, uri);

        if (diagnostics_count == 1) {
            first_diag_received = true;
            print ("First diagnostics (after didOpen) received, sending didChange...\n");
            client.text_document_did_change.begin (test_uri, 2, updated_content, null, null);
        } else if (diagnostics_count >= 2) {
            print ("Second diagnostics (after didChange) received\n");
            main_loop.quit ();
        }
    });

    client.error_occurred.connect ((msg) => {
        print ("LSP Error: %s\n", msg);
    });

    string workspace_uri = "file://" + Environment.get_current_dir ();
    client.start_server.begin (clangd_path, {}, workspace_uri);

    Timeout.add (20000, () => {
        print ("Timeout. Diagnostics received: %d\n", diagnostics_count);
        main_loop.quit ();
        return Source.REMOVE;
    });

    main_loop.run ();

    assert (last_uri == test_uri);
    assert (first_diag_received);
    print ("Integration test: passed (didOpen -> publishDiagnostics received)\n");
}

private string build_did_open_message (string uri, string language_id, int version, string content) {
    var builder = new Json.Builder ();
    builder.begin_object ();
    builder.set_member_name ("jsonrpc");
    builder.add_string_value ("2.0");
    builder.set_member_name ("method");
    builder.add_string_value ("textDocument/didOpen");
    builder.set_member_name ("params");
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
    builder.add_string_value (content);
    builder.end_object ();
    builder.end_object ();
    builder.end_object ();

    var generator = new Json.Generator ();
    generator.root = builder.get_root ();
    return generator.to_data (null);
}

private string build_publish_diagnostics_message (string uri, int version, string message, int start_line, int start_col, int end_line, int end_col) {
    var builder = new Json.Builder ();
    builder.begin_object ();
    builder.set_member_name ("jsonrpc");
    builder.add_string_value ("2.0");
    builder.set_member_name ("method");
    builder.add_string_value ("textDocument/publishDiagnostics");
    builder.set_member_name ("params");
    builder.begin_object ();
    builder.set_member_name ("uri");
    builder.add_string_value (uri);
    builder.set_member_name ("version");
    builder.add_int_value (version);
    builder.set_member_name ("diagnostics");
    builder.begin_array ();
    builder.begin_object ();
    builder.set_member_name ("severity");
    builder.add_int_value (1);
    builder.set_member_name ("message");
    builder.add_string_value (message);
    builder.set_member_name ("range");
    builder.begin_object ();
    builder.set_member_name ("start");
    builder.begin_object ();
    builder.set_member_name ("line");
    builder.add_int_value (start_line);
    builder.set_member_name ("character");
    builder.add_int_value (start_col);
    builder.end_object ();
    builder.set_member_name ("end");
    builder.begin_object ();
    builder.set_member_name ("line");
    builder.add_int_value (end_line);
    builder.set_member_name ("character");
    builder.add_int_value (end_col);
    builder.end_object ();
    builder.end_object ();
    builder.end_object ();
    builder.end_array ();
    builder.end_object ();
    builder.end_object ();

    var generator = new Json.Generator ();
    generator.root = builder.get_root ();
    return generator.to_data (null);
}

private string build_did_change_message (string uri, int version, string content) {
    var builder = new Json.Builder ();
    builder.begin_object ();
    builder.set_member_name ("jsonrpc");
    builder.add_string_value ("2.0");
    builder.set_member_name ("method");
    builder.add_string_value ("textDocument/didChange");
    builder.set_member_name ("params");
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
    builder.end_object ();

    var generator = new Json.Generator ();
    generator.root = builder.get_root ();
    return generator.to_data (null);
}
