public class Iide.PythonLspConfig : Iide.LspConfig {
    public override string command () {
        return "basedpyright-langserver";
    }

    public override string[] args () {
        return { "--stdio" };
    }

    public override Json.Node initialize_params (string? workspace_root, string? initial_uri) {
        var root_uri = workspace_root ?? "/";
        var params = """{
            "processId": null,
            "clientInfo": { "name": "iide", "version": "0.1.0" },
            "rootUri": "%s",
            "workspaceFolders": [
                { "uri": "%s", "name": "project" }
            ],
            "capabilities": {
                "textDocument": {
                "publishDiagnostics": { "relatedInformation": true }
                },
                "workspace": {
                "configuration": true
                },
                "window": { "workDoneProgress": true }
            },
            "initializationOptions": {
                "python": {},
                "settings": {
                "pyright": { "analysis": { "diagnosticMode": "workspace" } },
                "basedpyright": { "analysis": { "diagnosticMode": "workspace" } }
                }
            }
        }""".printf (root_uri, root_uri);
        var parser = new Json.Parser ();
        try {
            parser.load_from_data (params);
        } catch (GLib.Error e) {
            return new Json.Node (Json.NodeType.NULL);
        }
        return parser.get_root ();
    }

    public override Json.Node? server_response_result (Json.Object response) {
        string method = response.get_string_member ("method");
        if (method != "workspace/configuration") {
            return new Json.Node (Json.NodeType.NULL);
        }

        var items = response.get_object_member ("params").get_array_member ("items");
        var results = new Json.Array ();

        foreach (var item in items.get_elements ()) {
            var section = item.get_object ().get_string_member ("section");
            var settings = new Json.Object ();

            if (section == "basedpyright.analysis" || section == "python.analysis") {
                // Сервер уже внутри 'analysis', даем только параметры
                settings.set_string_member ("diagnosticMode", "workspace");
            } else if (section == "basedpyright" || section == "pyright" || section == "python") {
                // Сервер в корне, нужно добавить вложенность 'analysis'
                var analysis_obj = new Json.Object ();
                analysis_obj.set_string_member ("diagnosticMode", "workspace");
                settings.set_object_member ("analysis", analysis_obj);
            } else {
                // Для неизвестных секций лучше вернуть пустой объект, чтобы не сломать массив
                settings = new Json.Object ();
            }

            results.add_object_element (settings);
        }

        var results_node = new Json.Node (Json.NodeType.ARRAY);
        results_node.set_array (results);
        return results_node;
    }
}
