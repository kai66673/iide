public class Iide.CppLspConfig : Iide.LspConfig {
    public override string command () {
        return "clangd";
    }

    public override string[] args () {
        return {
                   "--background-index", // Индексация в фоне
                   "--clang-tidy", // Включает мощный линтер (генерирует тонну сообщений)
                   "--clang-tidy-checks=*", // Включит вообще все проверки, сообщений будет тысячи
                   "--background-index-priority=low", // Чтобы не вешать систему, но делать всё
                   "--all-scopes-completion", // Заставляет сервер глубже копать индексы
                   "--header-insertion=never"
        };
    }

    public override Json.Node initialize_params (string? workspace_root, string? initial_uri) {
        message ("CPP: initialize_params: " + workspace_root);
        var root_uri = "file:///home/kai/kaigit/ktexteditor";
        var params = """{
            "processId": null,
            "clientInfo": {
              "name": "Iide",
              "version": "1.0.1"
            },
            "rootPath": "%s",
            "rootUri": "%s",
            "capabilities": {
              "window": {
                "workDoneProgress": true
              },
              "workspace": {
                "applyEdit": true,
                "diagnostic": {
                  "refreshSupport": true
                },
                "workspaceEdit": {
                  "documentChanges": true
                },
                "didChangeConfiguration": {
                  "dynamicRegistration": true
                },
                "didChangeWatchedFiles": {
                  "dynamicRegistration": true
                },
                "symbol": {
                  "dynamicRegistration": true
                },
                "executeCommand": {
                  "dynamicRegistration": true
                }
              },
              "textDocument": {
                "diagnostic": {
                  "dynamicRegistration": true
                },
                "synchronization": {
                  "dynamicRegistration": true,
                  "willSave": true,
                  "willSaveWaitUntil": false,
                  "didSave": true
                },
                "completion": {
                  "dynamicRegistration": true,
                  "contextSupport": true,
                  "completionItem": {
                    "snippetSupport": false,
                    "commitCharactersSupport": true,
                    "documentationFormat": ["markdown", "plaintext"],
                    "deprecatedSupport": true,
                    "labelDetailsSupport": true
                  },
                  "completionItemKind": {
                    "valueSet": [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25]
                  }
                },
                "hover": {
                  "dynamicRegistration": true,
                  "contentFormat": ["markdown", "plaintext"]
                },
                "signatureHelp": {
                  "dynamicRegistration": true,
                  "signatureInformation": {
                    "documentationFormat": ["markdown", "plaintext"],
                    "parameterInformation": {
                      "labelOffsetSupport": true
                    }
                  }
                },
                "definition": {
                  "dynamicRegistration": true,
                  "linkSupport": true
                },
                "references": {
                  "dynamicRegistration": true
                },
                "documentSymbol": {
                  "dynamicRegistration": true,
                  "hierarchicalDocumentSymbolSupport": true
                },
                "codeAction": {
                  "dynamicRegistration": true
                },
                "publishDiagnostics": {
                  "relatedInformation": true,
                  "tagSupport": {
                    "valueSet": [1, 2]
                  },
                  "versionSupport": true
                }
              }
            },
            "initializationOptions": {
              "clangdFileStatus": true,
              "backgroundIndex": true,
              "compilationDatabasePath": "build",
              "fallbackFlags": ["-std=c++17", "-Iinclude"]
            }
          }
        """.printf (root_uri.replace ("file://", ""), root_uri);
        var parser = new Json.Parser ();
        try {
            parser.load_from_data (params);
        } catch (GLib.Error e) {
            return new Json.Node (Json.NodeType.NULL);
        }
        return parser.get_root ();
    }

    public override Json.Node? server_response_result (Json.Object response) {
        return new Json.Node (Json.NodeType.NULL);
    }
}
