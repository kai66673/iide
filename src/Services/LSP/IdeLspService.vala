using GLib;
using Gee;

public class Iide.IdeLspService : GLib.Object {
    private static IdeLspService? _instance;
    private Gee.HashMap<string, LspClient> clients;
    private Gee.HashMap<string, string> uri_to_client_key;
    private Gee.HashMap<string, int> document_versions;
    private Gee.HashMap<string, bool> client_starting;
    private Gee.ArrayList<PendingOpen> pending_opens;

    private LoggerService logger = LoggerService.get_instance ();

    public signal void diagnostics_updated (string uri, ArrayList<IdeLspDiagnostic> diagnostics);

    public class PendingOpen {
        public string uri;
        public string language_id;
        public string content;
        public string? workspace_root;
        public SourceView view;

        public PendingOpen (string uri, string language_id, string content, string? workspace_root, SourceView view) {
            this.uri = uri;
            this.language_id = language_id;
            this.content = content;
            this.workspace_root = workspace_root;
            this.view = view;
        }
    }

    // [ClientHash] -> [Token] -> LspTaskInfo
    private Gee.HashMap<int, Gee.HashMap<string, LspTaskInfo?>> progress_map =
        new Gee.HashMap<int, Gee.HashMap<string, LspTaskInfo?>> ();

    public signal void tasks_changed (Gee.List<LspTaskInfo?> active_tasks);

    construct {
        clients = new Gee.HashMap<string, LspClient> ();
        uri_to_client_key = new Gee.HashMap<string, string> ();
        document_versions = new Gee.HashMap<string, int> ();
        client_starting = new Gee.HashMap<string, bool> ();
        pending_opens = new Gee.ArrayList<PendingOpen> ();
    }

    public static unowned IdeLspService get_instance () {
        if (_instance == null) {
            _instance = new IdeLspService ();
        }
        return _instance;
    }

    public LspClient ? get_client_by_hash (int client_id) {
        foreach (var client in clients.values) {
            if (client.get_hash () == client_id) {
                return client;
            }
        }
        return null;
    }

    public void register_client (LspClient client) {
        int id = client.get_hash ();

        client.progress_updated.connect ((token, msg, perc, active) => {
            if (!progress_map.has_key (id))
                progress_map.set (id, new Gee.HashMap<string, LspTaskInfo?> ());

            var client_tasks = progress_map.get (id);

            if (active) {
                var info = LspTaskInfo () {
                    server_name = client.name (),
                    message = msg,
                    percentage = perc
                };
                client_tasks.set (token, info);
            } else {
                client_tasks.unset (token);
            }

            emit_tasks_changed ();
        });
    }

    private void emit_tasks_changed () {
        var all_tasks = new Gee.ArrayList<LspTaskInfo?> ();
        foreach (var client_map in progress_map.values) {
            foreach (var task in client_map.values) {
                all_tasks.add (task);
            }
        }
        tasks_changed (all_tasks);
    }

    public async void open_document (string uri, string language_id, string content, string? workspace_root, SourceView view) {
        var server_key = LspRegistry.get_lsp_id (language_id);
        if (server_key == null) {
            debug ("IdeLspService: No LSP server configured for language: %s", language_id);
            Idle.add (() => {
                view.setup_no_lsp_sync ();
                return Source.REMOVE;
            });
            return;
        }

        debug ("IdeLspService: Opening document %s (lang=%s)", uri, language_id);

        if (clients.has_key (server_key)) {
            var client = clients.get (server_key);
            uri_to_client_key.set (uri, server_key);
            document_versions.set (uri, 1);
            try {
                yield client.text_document_did_open (uri, language_id, 1, content);
            } catch (Error e) {
                logger.error ("LSP", "Failed to open document %s: %s".printf (uri, e.message));
            }

            Idle.add (() => {
                view.setup_lsp_sync (client);
                return Source.REMOVE;
            });

            return;
        }

        if (client_starting.get (server_key) == true) {
            pending_opens.add (new PendingOpen (uri, language_id, content, workspace_root, view));
            return;
        }

        client_starting.set (server_key, true);

        var config = LspRegistry.get_config (server_key);
        if (config == null) {
            client_starting.set (server_key, false);
            return;
        }

        var client = new LspClient (config);
        client.diagnostics_received.connect ((uri, diagnostics) => {
            diagnostics_updated (uri, diagnostics);
        });

        bool started = yield client.start_server_async (workspace_root);

        logger.info ("LSP", "Started server for %s: %b (%s)".printf (server_key, started, workspace_root));

        if (started) {
            clients.set (server_key, client);
            uri_to_client_key.set (uri, server_key);
            document_versions.set (uri, 1);
            try {
                yield client.text_document_did_open (uri, language_id, 1, content);
            } catch (Error e) {
                logger.error ("LSP", "Failed to open document %s: %s".printf (uri, e.message));
            }

            Idle.add (() => {
                view.setup_lsp_sync (client);
                return Source.REMOVE;
            });

            yield process_pending_opens ();
        } else {
            // TODO: restart logic...
            Idle.add (() => {
                view.setup_no_lsp_sync ();
                return Source.REMOVE;
            });

            warning ("IdeLspService: Failed to start LSP server for %s", server_key);
        }

        client_starting.set (server_key, false);
    }

    private async void process_pending_opens () {
        var opens_to_process = new ArrayList<PendingOpen> ();
        foreach (var open in pending_opens) {
            opens_to_process.add (open);
        }
        pending_opens.clear ();

        foreach (var open in opens_to_process) {
            yield open_document (open.uri, open.language_id, open.content, open.workspace_root, open.view);
        }
    }

    public async void change_document (string uri, string content, int? change_start = null, int? change_end = null) {
        var server_key = uri_to_client_key.get (uri);

        logger.debug ("LSP", "Changed doc: " + uri + " / server_key: " + server_key);
        if (server_key == null || !clients.has_key (server_key)) {
            return;
        }

        var client = clients.get (server_key);
        var version = document_versions.get (uri);
        document_versions.set (uri, version + 1);

        try {
            yield client.text_document_did_change (uri, version + 1, content);
        } catch (Error e) {
            logger.error ("LSP", "Failed to change document (FULL sync) %s: %s".printf (uri, e.message));
        }
    }

    public async void send_did_change (string uri, int version, Gee.ArrayList<PendingChange> changes) {
        var server_key = uri_to_client_key.get (uri);
        if (server_key == null || !clients.has_key (server_key)) {
            return;
        }

        var client = clients.get (server_key);
        try {
            yield client.send_did_change (uri, version, changes);
        } catch (Error e) {
            logger.error ("LSP", "Failed to change document (INCREMENTAL sync) %s: %s".printf (uri, e.message));
        }
    }

    public async void close_document (string uri) {
        var server_key = uri_to_client_key.get (uri);
        if (server_key == null || !clients.has_key (server_key)) {
            return;
        }

        var client = clients.get (server_key);
        try {
            yield client.text_document_did_close (uri);
        } catch (Error e) {
            logger.error ("LSP", "Failed to close document %s: %s".printf (uri, e.message));
        }

        uri_to_client_key.unset (uri);
        document_versions.unset (uri);
    }

    public LspClient ? get_client_for_uri (string uri) {
        var server_key = uri_to_client_key.get (uri);
        if (server_key == null) {
            return null;
        }
        return clients.get (server_key);
    }

    public async IdeLspCompletionResult ? request_completion (string uri,
                                                              int line,
                                                              int character,
                                                              string? trigger_character = null,
                                                              CompletionTriggerKind trigger_kind = INVOKED) {
        var client = get_client_for_uri (uri);
        if (client == null) {
            return null;
        }
        try {
            return yield client.request_completion (uri, line, character, trigger_character, trigger_kind);
        } catch (Error e) {
            logger.error ("LSP", "Failed to request completion for %s: %s".printf (uri, e.message));
            return null;
        }
    }

    public async string ? request_hover (string uri, int line, int character) {
        var client = get_client_for_uri (uri);
        if (client == null) {
            logger.debug ("HOVER", "client is null!");
            return null;
        }
        try {
            return yield client.request_hover (uri, line, character);
        } catch (Error e) {
            logger.error ("LSP", "Failed to request hover for %s: %s".printf (uri, e.message));
            return null;
        }
    }

    public async Gee.ArrayList<IdeLspLocation>? goto_definition (string uri, int line, int character) {
        var client = get_client_for_uri (uri);
        if (client == null)return null;
        try {
            return yield client.request_definition (uri, line, character);
        } catch (Error e) {
            logger.error ("LSP", "Failed to request definition for %s: %s".printf (uri, e.message));
            return null;
        }
    }
}
