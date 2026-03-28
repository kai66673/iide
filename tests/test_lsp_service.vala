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

    var client = new Iide.LSPClient ();
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
