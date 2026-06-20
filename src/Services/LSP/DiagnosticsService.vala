/*
*/
public class Iide.DiagnosticsService : Object {
    private static DiagnosticsService? _instance;

    // Группировка: [ClientID] -> [FileURI] -> [Список диагностик]
    private Gee.HashMap<string, Gee.HashMap<string, Gee.List<LspDiagnostic>>> server_map;
    private uint update_timeout_id = 0;

    public signal void diagnostics_updated (string server_name, string uri);
    public signal void lsp_stopped ();
    public signal void server_stopped (string server_name);
    public signal void total_count_changed (int total_errors, int total_warnings);

    public static DiagnosticsService get_instance () {
        if (_instance == null)
            _instance = new DiagnosticsService ();
        return _instance;
    }

    private DiagnosticsService () {
        server_map = new Gee.HashMap<string, Gee.HashMap<string, Gee.List<LspDiagnostic>>> ();
        this.lsp_stopped.connect (() => {
            server_map.clear ();
        });
    }

    /**
     * Возвращает карту всех диагностик.
     * Мы возвращаем её как Map, чтобы панель могла перебрать Entry (серверы и их файлы).
     */
    public Gee.Map<string, Gee.HashMap<string, Gee.List<LspDiagnostic>>> get_server_map () {
        return server_map;
    }

    /**
     * Возвращает список диагностик для конкретного файла от конкретного LSP-клиента.
     */
    public Gee.List<LspDiagnostic>? get_diagnostics_for_file (string server_name, string uri) {
        if (server_map.has_key (server_name)) {
            var client_files = server_map.get (server_name);
            if (client_files.has_key (uri)) {
                // Возвращаем список (в Vala Gee.List — это ссылочный тип)
                return client_files.get (uri);
            }
        }
        return null;
    }

    public void update_diagnostics (string server_name, string uri, Gee.List<LspDiagnosticPair?> list) {
        if (!server_map.has_key (server_name)) {
            server_map.set (server_name, new Gee.HashMap<string, Gee.List<LspDiagnostic>> ());
        }

        var client_files = server_map.get (server_name);

        if (list.size == 0) {
            client_files.unset (uri);
        } else {
            var d_list = new Gee.ArrayList<LspDiagnostic> ();
            foreach (var d in list) {
                d_list.add (d.diagnostic);
            }
            client_files.set (uri, d_list);
        }

        diagnostics_updated (server_name, uri);

        // Вместо немедленного emit_totals():
        if (update_timeout_id == 0) {
            update_timeout_id = Timeout.add (300, () => {
                emit_totals ();
                update_timeout_id = 0;
                return Source.REMOVE;
            });
        }
    }

    // Удаление всех данных сервера при его отключении
    public void remove_client (string server_name) {
        if (server_map.unset (server_name)) {
            emit_totals ();
            server_stopped (server_name);
        }
    }

    private void emit_totals () {
        int e = 0; int w = 0;
        foreach (var client_files in server_map.values) {
            foreach (var list in client_files.values) {
                foreach (var d in list) {
                    if (d.severity == 1)e++;
                    else w++;
                }
            }
        }
        total_count_changed (e, w);
    }
}
