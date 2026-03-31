using GLib;
using Gee;
using GtkSource;

namespace Iide {

public class IdeLspManager : GLib.Object {
    private static IdeLspManager? _instance;
    private IdeLspService lsp_service;

    public static unowned IdeLspManager get_instance () {
        if (_instance == null) {
            _instance = new IdeLspManager ();
        }
        return _instance;
    }

    construct {
        lsp_service = IdeLspService.get_instance ();
    }

    public async void open_document (string uri, string language_id, string content, string? workspace_root) {
        yield lsp_service.open_document (uri, language_id, content, workspace_root);
    }

    public async void change_document (string uri, string content, int? change_start = null, int? change_end = null) {
        yield lsp_service.change_document (uri, content, change_start, change_end);
    }

    public async void close_document (string uri) {
        yield lsp_service.close_document (uri);
    }

    public void set_language_config (string language_id, string command, string[] args, string? workspace_root = null) {
        lsp_service.set_language_config (language_id, command, args, workspace_root);
    }

    public IdeLspClient? get_client_for_uri (string uri) {
        return lsp_service.get_client_for_uri (uri);
    }

    public void connect_diagnostics (DiagnosticsCallback diagnostics_callback) {
        lsp_service.diagnostics_updated.connect ((uri, diagnostics) => {
            diagnostics_callback (uri, diagnostics);
        });
    }

    public string? get_language_id_for_file (GLib.File file) {
        string filename = file.get_basename () ?? "";
        
        switch (filename) {
        case "CMakeLists.txt":
            return "cmake";
        case ".gitignore":
            return "git-config";
        case "meson.build":
            return "meson";
        case "PKGBUILD":
            return "bash";
        default:
            break;
        }

        string path = file.get_path () ?? "";
        int dot_pos = path.last_index_of (".");
        if (dot_pos >= 0 && dot_pos < path.length - 1) {
            string ext = path[dot_pos + 1:path.length].down ();
            switch (ext) {
            case "py":
                return "python";
            case "c":
            case "h":
                return "c";
            case "cpp":
            case "cc":
            case "cxx":
            case "hpp":
            case "hxx":
                return "cpp";
            case "vala":
            case "vapi":
                return "vala";
            case "rs":
                return "rust";
            case "go":
                return "go";
            case "js":
            case "ts":
                return "javascript";
            case "json":
                return "json";
            case "xml":
                return "xml";
            case "html":
            case "htm":
                return "html";
            case "css":
                return "css";
            case "md":
            case "markdown":
                return "markdown";
            case "sh":
            case "bash":
            case "zsh":
                return "bash";
            case "yaml":
            case "yml":
                return "yaml";
            }
        }
        
        return null;
    }

    public delegate void DiagnosticsCallback (string uri, Gee.ArrayList<IdeLspDiagnostic> diagnostics);
}

}