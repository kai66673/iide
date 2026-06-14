/*
*/

public class Iide.LanguageRegistry : GLib.Object {
    private static LanguageRegistry? instance = null;
    
    // СЛОЙ 1: Захардкоженный дефолтный JSON в исходном коде приложения.
    // Сюда закладываем базовые настройки, чтобы IDE работала из коробки.
    private const string DEFAULT_LANGUAGES_JSON = """
    {
        "languages": {
            "python": {
                "display_name": "Python",
                "extensions": [".py", ".pyi"],
                "lsp": {
                    "command": ["basedpyright-langserver", "--stdio"],
                    "capabilities": { "formatting": false, "hover": true, "completion": true },
                    "initialize_template": {
                        "processId": null,
                        "clientInfo": { "name": "iide", "version": "0.1.0" },
                        "rootUri": "${WORKSPACE_ROOT}",
                        "workspaceFolders": [
                            { "uri": "${WORKSPACE_ROOT}", "name": "project" }
                        ],
                        "capabilities": {
                            "textDocument": {
                            "publishDiagnostics": { "relatedInformation": true },
                            "documentSymbol": {
                                "hierarchicalDocumentSymbolSupport": true,
                                "symbolKind": { "valueSet": [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26] }
                            }
                            },
                            "workspace": { "configuration": true },
                            "window": { "workDoneProgress": true }
                        },
                        "initializationOptions": {
                            "python": {},
                            "settings": {
                            "pyright": { "analysis": { "diagnosticMode": "workspace" } },
                            "basedpyright": { "analysis": { "diagnosticMode": "workspace" } }
                            }
                        }
                    },
                    "section_settings": {
                        "basedpyright.analysis": { "diagnosticMode": "workspace" },
                        "python.analysis": { "diagnosticMode": "workspace" },
                        "pyright.analysis": { "diagnosticMode": "workspace" },
                        "basedpyright": { "analysis": { "diagnosticMode": "workspace" } },
                        "pyright": { "analysis": { "diagnosticMode": "workspace" } },
                        "python": { "analysis": { "diagnosticMode": "workspace" } }
                    }
                },
                "formatting": { "engine": "cli", "command": "ruff format - --stdin-filename '%s'" }
            },
            "cpp": {
                "display_name": "C/C++",
                "extensions": [".cpp", ".hpp", ".c", ".h", ".cc"],
                "lsp": {
                    "command": ["clangd", "--background-index", "--clang-tidy", "--clang-tidy-checks=*", "--background-index-priority=low", "--all-scopes-completion", "--header-insertion=never"],
                    "capabilities": { "formatting": true, "hover": true, "completion": true },
                    "initialize_template": {
                        "processId": null,
                        "clientInfo": {
                            "name": "Iide",
                            "version": "1.0.1"
                        },
                        "rootPath": "${WORKSPACE_ROOT}",
                        "rootUri": "${WORKSPACE_ROOT}",
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
                },
                "formatting": { "engine": "lsp" }
            }
        }
    }
    """;

    // JSON-объект, в котором мы будем собирать итоговый пирог настроек
    private Json.Object merged_languages_node;
    
    private Gee.HashMap<string, LanguageProfile> profiles;
    private Gee.HashMap<string, string> extension_to_lang_id;

    public static LanguageRegistry get_instance () {
        if (instance == null) {
            instance = new LanguageRegistry ();
        }
        return instance;
    }

    private LanguageRegistry () {
        Object ();
        this.profiles = new Gee.HashMap<string, LanguageProfile> ();
        this.extension_to_lang_id = new Gee.HashMap<string, string> ();
        
        // На старте инициализируем реестр базовым трехуровневым конфигом (без проекта)
        this.reload_registry (null);
    }

    /**
        * Главный метод перезагрузки конфигурационной матрицы.
        * @param project_root_path Путь к открытому проекту (или null, если проект не открыт)
        */
    public void reload_registry (string? project_root_path) {
        try {
            var parser = new Json.Parser ();

            // --- ШАГ 1: Загружаем базовый хардкод ---
            parser.load_from_data (DEFAULT_LANGUAGES_JSON, -1);
            var base_root = parser.get_root ().get_object ();
            this.merged_languages_node = this.clone_json_object (base_root.get_object_member ("languages"));

            // --- ШАГ 2: Накатываем Глобальный конфиг из ~/.config/iide/languages.json ---
            string global_config_dir = Environment.get_user_config_dir (); // Возвращает путь к ~/.config
            string global_config_path = Path.build_filename (global_config_dir, "iide", "languages.json");

            if (FileUtils.test (global_config_path, FileTest.EXISTS)) {
                var global_parser = new Json.Parser ();
                global_parser.load_from_file (global_config_path);
                var global_root = global_parser.get_root ().get_object ();
                
                if (global_root.has_member ("languages")) {
                    var global_langs = global_root.get_object_member ("languages");
                    // Слияние: Глобальный конфиг -> поверх хардкода
                    this.deep_merge_json_objects (this.merged_languages_node, global_langs);
                    LoggerService.get_instance ().info ("Registry", "Global configuration overrides applied from ~/.config/iide/languages.json");
                }
            }

            // --- ШАГ 3: Накатываем Конфиг проекта из <project>/.iide/languages.json ---
            if (project_root_path != null && project_root_path.length > 0) {
                string project_config_path = GLib.Path.build_filename (project_root_path, ".iide", "languages.json");

                if (FileUtils.test (project_config_path, FileTest.EXISTS)) {
                    var project_parser = new Json.Parser ();
                    project_parser.load_from_file (project_config_path);
                    var project_root = project_parser.get_root ().get_object ();
                    
                    if (project_root.has_member ("languages")) {
                        var project_langs = project_root.get_object_member ("languages");
                        // Слияние: Проектный конфиг -> поверх объединенного пирога
                        this.deep_merge_json_objects (this.merged_languages_node, project_langs);
                        LoggerService.get_instance ().info ("Registry", "Project-level configuration overrides applied.");
                    }
                }
            }

            // --- ФИНАЛ: Перестраиваем типизированные профили Vala ---
            this.rebuild_profiles_from_json (this.merged_languages_node);
            LoggerService.get_instance ().info ("Registry", "Language profiles successfully built (3-tier pipeline completed).");

        } catch (GLib.Error e) {
            LoggerService.get_instance ().error ("Registry", "Failed to build 3-tier configuration matrix: %s".printf (e.message));
        }
    }

    // Рекурсивный глубокий merge JSON
    private void deep_merge_json_objects (Json.Object target, Json.Object source) {
        foreach (string member in source.get_members ()) {
            var source_node = source.get_member (member);

            if (source_node.get_node_type () == Json.NodeType.OBJECT && target.has_member (member)) {
                var target_child = target.get_object_member (member);
                var source_child = source_node.get_object ();
                this.deep_merge_json_objects (target_child, source_child);
            } else {
                target.set_member (member, source_node.copy ());
            }
        }
    }

    // Клонирование JSON-ноды для изоляции иммутабельности
    private Json.Object clone_json_object (Json.Object source) {
        var generator = new Json.Generator ();
        var node = new Json.Node (Json.NodeType.OBJECT);
        node.set_object (source);
        generator.set_root (node);
        string json_str = generator.to_data (null);
        
        var parser = new Json.Parser ();
        try {
            parser.load_from_data (json_str, -1);
            return parser.get_root ().get_object ();
        } catch {
            return new Json.Object ();
        }
    }

    // Разбор результирующего JSON-объекта в хэш-мапы (типизированные структуры)
    private void rebuild_profiles_from_json (Json.Object languages_node) {
        this.profiles.clear ();
        this.extension_to_lang_id.clear ();

        foreach (string lang_id in languages_node.get_members ()) {
            var lang_json = languages_node.get_object_member (lang_id);
            
            var profile = new LanguageProfile ();
            profile.id = lang_id;
            profile.display_name = lang_json.get_string_member ("display_name");

            var exts_array = lang_json.get_array_member ("extensions");
            foreach (var ext_node in exts_array.get_elements ()) {
                string ext = ext_node.get_string ();
                profile.extensions.add (ext);
                this.extension_to_lang_id.set (ext, lang_id);
            }

            if (lang_json.has_member ("lsp")) {
                var lsp_json = lang_json.get_object_member ("lsp");
                var lsp_cfg = new LspConfig ();
                
                var cmd_array = lsp_json.get_array_member ("command");
                string[] cmd_args = {};
                foreach (var arg_node in cmd_array.get_elements ()) { cmd_args += arg_node.get_string (); }
                lsp_cfg.command = cmd_args;

                if (lsp_json.has_member ("capabilities")) {
                    var caps = lsp_json.get_object_member ("capabilities");
                    if (caps.has_member ("formatting")) lsp_cfg.capability_formatting = caps.get_boolean_member ("formatting");
                    if (caps.has_member ("hover")) lsp_cfg.capability_hover = caps.get_boolean_member ("hover");
                    if (caps.has_member ("completion")) lsp_cfg.capability_completion = caps.get_boolean_member ("completion");
                }

                // ===================================================================
                // ДИНАМИЧЕСКИЙ РАЗБОР: Читаем шаблон инициализации и мапу секций
                // ===================================================================
                if (lsp_json.has_member ("initialize_template")) {
                    var node = lsp_json.get_member ("initialize_template").copy ();
                    lsp_cfg.initialize_template = node.get_object ();
                }
                if (lsp_json.has_member ("section_settings")) {
                    var node = lsp_json.get_member ("section_settings").copy ();
                    lsp_cfg.section_settings = node.get_object ();
                }

                profile.lsp = lsp_cfg;
            }

            if (lang_json.has_member ("formatting")) {
                var fmt_json = lang_json.get_object_member ("formatting");
                var fmt_cfg = new FeatureConfig ();
                fmt_cfg.engine = fmt_json.get_string_member ("engine");
                if (fmt_json.has_member ("command")) fmt_cfg.command = fmt_json.get_string_member ("command");
                profile.formatting = fmt_cfg;
            }

            this.profiles.set (lang_id, profile);
        }
    }

    public LanguageProfile? get_profile (string lang_id) {
        /// TODO: !DEBUG
        if (this.profiles.has_key (lang_id))
            return this.profiles.get (lang_id);
        return null;
    }

    public string get_lang_id_for_filename (string filename) {
        string ext = "";
        int dot_index = filename.last_index_of_char ('.');
        if (dot_index != -1) {
            ext = filename.substring (dot_index);
        }
        return this.extension_to_lang_id.get (ext.down ()) ?? "plaintext";
    }
}
