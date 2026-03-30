/*
 * LSPManager.vala
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

public class Iide.LSPManager : GLib.Object {
    private static LSPManager? _instance;
    private Gee.HashMap<string, Iide.LSPClient> servers;
    private Gee.HashMap<string, string> uri_to_server;
    private Gee.HashMap<string, int> document_versions;
    private Gee.HashMap<string, bool> server_starting;
    private Gee.ArrayList<PendingOpen> pending_opens;
    private Iide.ProjectManager project_manager;

    private class PendingOpen {
        public string uri;
        public string language_id;
        public string content;
        public string? workspace_root;

        public PendingOpen (string uri, string language_id, string content, string? workspace_root) {
            this.uri = uri;
            this.language_id = language_id;
            this.content = content;
            this.workspace_root = workspace_root;
        }
    }

    public signal void diagnostics_updated (string uri, Gee.ArrayList<LSPClient.Diagnostic> diagnostics);

    public static unowned LSPManager get_instance () {
        if (_instance == null) {
            _instance = new LSPManager ();
        }
        return _instance;
    }

    construct {
        servers = new Gee.HashMap<string, Iide.LSPClient> ();
        uri_to_server = new Gee.HashMap<string, string> ();
        document_versions = new Gee.HashMap<string, int> ();
        server_starting = new Gee.HashMap<string, bool> ();
        pending_opens = new Gee.ArrayList<PendingOpen> ();
        project_manager = Iide.ProjectManager.get_instance ();
    }

    public async void open_document (string uri, string language_id, string content, string? workspace_root) {
        var server_key = get_server_key_for_language (language_id);
        if (server_key == null) {
            return;
        }

        debug ("LSPManager: Opening document %s (lang=%s, workspace=%s)", uri, language_id, workspace_root);

        if (servers.has_key (server_key)) {
            debug ("LSPManager: Reusing existing server '%s'", server_key);
            var client = servers.get (server_key);
            uri_to_server.set (uri, server_key);
            document_versions.set (uri, 1);
            client.text_document_did_open (uri, language_id, 1, content);
            return;
        }

        if (server_starting.has_key (server_key) && server_starting.get (server_key)) {
            debug ("LSPManager: Server '%s' is starting, queueing document", server_key);
            pending_opens.add (new PendingOpen (uri, language_id, content, workspace_root));
            return;
        }

        debug ("LSPManager: Starting server '%s'", server_key);
        pending_opens.add (new PendingOpen (uri, language_id, content, workspace_root));
        yield ensure_server_async (server_key, workspace_root);
    }

    private async void ensure_server_async (string server_key, string? workspace_root) {
        if (server_starting.has_key (server_key) && server_starting.get (server_key)) {
            debug ("LSPManager: Server '%s' already starting, skipping", server_key);
            return;
        }

        server_starting.set (server_key, true);

        var config = project_manager.get_language_config (server_key);
        if (config != null) {
            string? cmd = Environment.find_program_in_path (config.server_command[0]);
            if (cmd == null) {
                warning ("LSP server '%s' not found", config.server_command[0]);
                server_starting.unset (server_key);
                process_pending_opens (server_key);
                return;
            }

            var client = new Iide.LSPClient ();
            client.diagnostics_received.connect ((uri, diags) => {
                diagnostics_updated (uri, diags);
            });

            string[] args = {};
            for (int i = 1; i < config.server_command.length; i++) {
                args += config.server_command[i];
            }

            bool started = yield client.start_server (cmd, args, workspace_root);

            if (started) {
                servers.set (server_key, client);
                message ("LSP server '%s' started successfully", server_key);
            } else {
                warning ("Failed to start LSP server '%s'", server_key);
            }

            server_starting.unset (server_key);
            process_pending_opens (server_key);
            return;
        } else {
            warning ("No language config found for '%s'", server_key);
            server_starting.unset (server_key);
            process_pending_opens (server_key);
        }

        server_starting.unset (server_key);
        process_pending_opens (server_key);
    }

    private void process_pending_opens (string server_key) {
        var to_remove = new Gee.ArrayList<int> ();

        for (int i = 0; i < pending_opens.size; i++) {
            var item = pending_opens.get (i);
            var cfg_key = get_server_key_for_language (item.language_id);
            if (cfg_key == server_key) {
                var client = servers.get (server_key);
                if (client != null) {
                    uri_to_server.set (item.uri, server_key);
                    document_versions.set (item.uri, 1);
                    client.text_document_did_open (item.uri, item.language_id, 1, item.content);
                }
                to_remove.add (i);
            }
        }

        for (int i = to_remove.size - 1; i >= 0; i--) {
            pending_opens.remove_at (to_remove.get (i));
        }
    }

    public async void change_document (string uri, string content) {
        string? server_key = uri_to_server.get (uri);
        if (server_key == null) {
            return;
        }

        var client = servers.get (server_key);
        if (client == null) {
            return;
        }

        int version = document_versions.get (uri);
        version++;
        document_versions.set (uri, version);

        client.text_document_did_change (uri, version, content);
    }

    public async void close_document (string uri) {
        uri_to_server.unset (uri);
        document_versions.unset (uri);
    }

    private string ? get_server_key_for_language (string language_id) {
        var config = project_manager.get_language_config (language_id);
        if (config != null) {
            return config.language_id;
        }
        return null;
    }

    public string ? get_language_id_for_file (GLib.File file) {
        string filename = file.get_basename () ?? "";

        foreach (var config in project_manager.get_language_configs ()) {
            foreach (var pattern in config.file_patterns) {
                if (pattern_matches (pattern, filename)) {
                    return config.language_id;
                }
            }
        }
        return null;
    }

    private bool pattern_matches (string pattern, string filename) {
        if (pattern.has_prefix ("*.")) {
            string ext = pattern.substring (1);
            return filename.has_suffix (ext);
        }
        return filename == pattern;
    }
}
