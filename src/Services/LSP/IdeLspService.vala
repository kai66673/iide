using GLib;
using Gee;

public class Iide.IdeLspService : GLib.Object {
    private static IdeLspService? _instance;
    private Gee.HashMap<string, LspClient> clients;
    private Gee.HashMap<string, string> uri_to_client_key;
    private Gee.HashMap<string, int> document_versions;
    private Gee.HashMap<string, bool> client_starting;
    private Gee.ArrayList<PendingOpen> pending_opens;
    private Gee.HashMap<string, LanguageConfig> language_configs;

    private LoggerService logger = LoggerService.get_instance ();

    public signal void diagnostics_updated (string uri, ArrayList<IdeLspDiagnostic> diagnostics);

    public class PendingOpen {
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

    public class LanguageConfig {
        public string command;
        public string[] args;
        public string? workspace_root;

        public LanguageConfig (string command, string[] args, string? workspace_root = null) {
            this.command = command;
            this.args = args;
            this.workspace_root = workspace_root;
        }
    }

    private void init_language_configs () {
        language_configs.set ("python", new LanguageConfig ("basedpyright-langserver", { "--stdio" }));
        language_configs.set ("python3", new LanguageConfig ("basedpyright-langserver", { "--stdio" }));
        language_configs.set ("cpp", new LanguageConfig ("clangd", new string[0]));
        language_configs.set ("c++", new LanguageConfig ("clangd", new string[0]));
        language_configs.set ("c", new LanguageConfig ("clangd", new string[0]));
        language_configs.set ("vala", new LanguageConfig ("vala-language-server", new string[0]));
        language_configs.set ("rust", new LanguageConfig ("rust-analyzer", new string[0]));
        language_configs.set ("go", new LanguageConfig ("gopls", new string[0]));
    }

    construct {
        clients = new Gee.HashMap<string, LspClient> ();
        uri_to_client_key = new Gee.HashMap<string, string> ();
        document_versions = new Gee.HashMap<string, int> ();
        client_starting = new Gee.HashMap<string, bool> ();
        pending_opens = new Gee.ArrayList<PendingOpen> ();
        language_configs = new Gee.HashMap<string, LanguageConfig> ();

        init_language_configs ();
    }

    public static unowned IdeLspService get_instance () {
        if (_instance == null) {
            _instance = new IdeLspService ();
        }
        return _instance;
    }

    public async void open_document (string uri, string language_id, string content, string? workspace_root) {
        var server_key = get_server_key_for_language (language_id);
        if (server_key == null) {
            debug ("IdeLspService: No LSP server configured for language: %s", language_id);
            return;
        }

        debug ("IdeLspService: Opening document %s (lang=%s)", uri, language_id);

        if (clients.has_key (server_key)) {
            var client = clients.get (server_key);
            uri_to_client_key.set (uri, server_key);
            document_versions.set (uri, 1);
            yield client.text_document_did_open (uri, language_id, 1, content);

            return;
        }

        if (client_starting.get (server_key) == true) {
            pending_opens.add (new PendingOpen (uri, language_id, content, workspace_root));
            return;
        }

        client_starting.set (server_key, true);

        var config = language_configs.get (server_key);
        if (config == null) {
            client_starting.set (server_key, false);
            return;
        }

        var client = new LspClient ();
        client.diagnostics_received.connect ((uri, diagnostics) => {
            diagnostics_updated (uri, diagnostics);
        });

        bool started = yield client.start_server_async (config.command, config.args, workspace_root ?? config.workspace_root);

        logger.info ("LSP", "Started server for %s: %b (%s -- %s)".printf (server_key, started, workspace_root, config.workspace_root));

        if (started) {
            clients.set (server_key, client);
            uri_to_client_key.set (uri, server_key);
            document_versions.set (uri, 1);
            yield client.text_document_did_open (uri, language_id, 1, content);

            yield process_pending_opens ();
        } else {
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
            yield open_document (open.uri, open.language_id, open.content, open.workspace_root);
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

        yield client.text_document_did_change (uri, version + 1, content);
    }

    public async void send_did_change (string uri, int version, Gee.ArrayList<PendingChange> changes) {
        var server_key = uri_to_client_key.get (uri);
        if (server_key == null || !clients.has_key (server_key)) {
            return;
        }

        var client = clients.get (server_key);
        yield client.send_did_change (uri, version, changes);
    }

    public async void close_document (string uri) {
        var server_key = uri_to_client_key.get (uri);
        if (server_key == null || !clients.has_key (server_key)) {
            return;
        }

        var client = clients.get (server_key);
        yield client.text_document_did_close (uri);

        uri_to_client_key.unset (uri);
        document_versions.unset (uri);
    }

    private string ? get_server_key_for_language (string language_id) {
        if (language_configs.has_key (language_id)) {
            return language_id;
        }

        if (language_id.down ().contains ("python")) {
            return "python";
        }
        if (language_id.down ().contains ("c++") || language_id.down ().contains ("cpp")) {
            return "cpp";
        }
        if (language_id.down ().contains ("c")) {
            return "c";
        }

        return null;
    }

    public void set_language_config (string language_id, string command, string[] args, string? workspace_root = null) {
        language_configs.set (language_id, new LanguageConfig (command, args, workspace_root));
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
        return yield client.request_completion (uri, line, character, trigger_character, trigger_kind);
    }

    public async string ? request_hover (string uri, int line, int character) {
        var client = get_client_for_uri (uri);
        if (client == null) {
            logger.debug ("HOVER", "client is null!");
            return null;
        }
        return yield client.request_hover (uri, line, character);
    }

    public async Gee.ArrayList<IdeLspLocation>? goto_definition (string uri, int line, int character) {
        var client = get_client_for_uri (uri);
        if (client == null)return null;
        return yield client.request_definition (uri, line, character);
    }
}
