using GLib;
using Json;
using Gee;

namespace Iide {

    // Перечисление фич для строгой типизации маршрутов
    [Flags]
    public enum LspFeatures {
        DIAGNOSTICS,
        COMPLETION,
        FORMATTING,
        CODE_ACTIONS,
        DEFINTION,
        HOVER
    }

    // Легковесный класс для хранения карты обязанностей конкретного языка
    public class LspLanguageRouter : GLib.Object {
        // Инвертированная карта: [Имя сервера] -> [Битовая маска фич (LspFeatures)]
        private Gee.HashMap<string, LspFeatures> server_features;

        public LspLanguageRouter () {
            this.server_features = new Gee.HashMap<string, LspFeatures> ();
        }

        /**
         * Добавить маршрут. Теперь feature может быть комбинацией:
         * router.add_route (LspFeatures.DIAGNOSTICS + LspFeatures.HOVER, "pyright");
         */
        public void add_server_feature (LspFeatures feature, string server_name) {
            if (!this.server_features.has_key (server_name)) {
                this.server_features.set (server_name, feature);
            } else {
                // Объединяем существующие флаги сервера с новыми через оператор +
                this.server_features.set (server_name, this.server_features.get (server_name) + feature);
            }
        }

        /**
         * Получить все уникальные серверы, назначенные на этот язык.
         * Теперь это работает мгновенно через возврат всех ключей карты.
         */
        public Gee.Set<string> get_all_assigned_servers () {
            return this.server_features.keys;
        }

        /**
         * Дополнительный полезный метод: проверить, поддерживает ли сервер конкретную фичу
         */
        public bool server_has_feature (string server_name, LspFeatures feature) {
            if (!this.server_features.has_key (server_name)) {
                return false;
            }
            // Используем оператор 'in' для проверки битовой маски
            return feature in this.server_features.get (server_name);
        }

        public LspFeatures features_for_server_name (string server_name) {
            if (this.server_features.has_key (server_name))
                return this.server_features.get(server_name);
            LspFeatures features = 0;
            return features;
        }
    }

    public class LanguageRegistry : GLib.Object {
        private static LanguageRegistry? _instance = null;

        // Встроенный глобальный JSON по умолчанию
        private const string DEFAULT_LANGUAGES_JSON = """
{
  "servers": {
    "basedpyright": {
      "command": ["basedpyright-langserver", "--stdio"],
      "capability_completion": true,
      "capability_hover": true,
      "capability_formatting": false,
      "initialize_template": {
        "processId": null,
        "clientInfo": { "name": "iide", "version": "0.1.0" },
        "rootUri": "${WORKSPACE_ROOT}",
        "workspaceFolders": [{ "uri": "${WORKSPACE_ROOT}", "name": "project" }],
        "capabilities": {
          "textDocument": {
            "publishDiagnostics": { "relatedInformation": true },
            "documentSymbol": {
              "hierarchicalDocumentSymbolSupport": true,
              "symbolKind": {
                "valueSet": [
                  1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18,
                  19, 20, 21, 22, 23, 24, 25, 26
                ]
              }
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
    "ruff": {
      "command": ["ruff", "server"],
      "capability_completion": false,
      "capability_hover": false,
      "capability_formatting": true,
      "initialize_template": {
        "processId": null,
        "rootUri": "${WORKSPACE_ROOT}",
        "capabilities": {
          "textDocument": {
            "diagnostic": {
              "dynamicRegistration": false
            },
            "codeAction": {
              "dynamicRegistration": false,
              "codeActionLiteralSupport": {
                "codeActionKind": {
                  "valueSet": ["quickfix", "refactor", "source.organizeImports"]
                }
              },
              "resolveSupport": {
                "properties": ["edit"]
              }
            }
          }
        },
        "initializationOptions": {
          "settings": {
            "logLevel": "info",
            "lint": {
              "enable": true,
              "preview": false
            },
            "format": {
              "enable": true
            }
          }
        }
      }
    }
  },
  "routing": {
    "python": {
      "diagnostics": ["basedpyright", "ruff"],
      "completion": ["basedpyright"],
      "formatting": ["ruff"],
      "code_actions": ["basedpyright", "ruff"],
      "definition": ["basedpyright"],
      "hover": ["basedpyright"]
    }
  }
}
        """;

        // Результирующие смерженные JSON-структуры
        private Json.Object merged_servers;
        private Json.Object merged_routing;

        public static unowned LanguageRegistry get_instance () {
            if (_instance == null) {
                _instance = new LanguageRegistry ();
            }
            return _instance;
        }

        private LanguageRegistry () {
            this.merged_servers = new Json.Object ();
            this.merged_routing = new Json.Object ();
            this.reset_to_defaults ();
        }

        /**
         * Сброс матриц до встроенных заводских значений приложения
         */
        private void reset_to_defaults () {
            var parser = new Json.Parser ();
            try {
                parser.load_from_data (DEFAULT_LANGUAGES_JSON, -1);
                var root = parser.get_root ().get_object ();
                
                this.merged_servers = root.dup_member ("servers").get_object ();
                this.merged_routing = root.dup_member ("routing").get_object ();
            } catch (GLib.Error e) {
                LoggerService.get_instance ().error ("LSP", "Failed to parse DEFAULT_LANGUAGES_JSON: " + e.message);
            }
        }

        /**
         * КРИТИЧЕСКИЙ МЕТОД: Накат локального lsp.json воркспейса на дефолтную матрицу [INDEX]
         */
        public void load_project_lsp_matrix (string lsp_json_path) {
            // 1. Возвращаем реестр в исходное чистое дефолтное состояние
            this.reset_to_defaults ();

            if (!FileUtils.test (lsp_json_path, FileTest.EXISTS)) {
                LoggerService.get_instance ().info ("LSP", "Local lsp.json not found. Running with global stock profile.");
                return;
            }

            var parser = new Json.Parser ();
            try {
                parser.load_from_file (lsp_json_path);
                var local_root = parser.get_root ().get_object ();

                // 2. Выполняем рекурсивное слияние секции серверов [INDEX]
                if (local_root.has_member ("servers")) {
                    var local_servers = local_root.get_object_member ("servers");
                    this.deep_merge_objects (this.merged_servers, local_servers);
                }

                // 3. Выполняем слияние секции маршрутизации [INDEX]
                if (local_root.has_member ("routing")) {
                    var local_routing = local_root.get_object_member ("routing");
                    this.deep_merge_objects (this.merged_routing, local_routing);
                }

                LoggerService.get_instance ().info ("LSP", "Successfully executed deep merge of local lsp.json configuration.");

            } catch (GLib.Error e) {
                LoggerService.get_instance ().error ("LSP", "Failed to merge workspace lsp.json: " + e.message);
            }
        }

        /**
         * ГЕТТЕР: Сборка динамического LspConfig для конкретного сервера на основе смерженного JSON [INDEX]
         */
        public LspConfig? get_config_for_server (string server_name) {
            if (!this.merged_servers.has_member (server_name)) return null;
            
            var server_json_obj = this.merged_servers.get_object_member (server_name);
            // Вызываем ваш нативный фабричный метод, который мы научили читать поля, шаблоны и секции настроек! [INDEX]
            return LspConfig.from_json (server_json_obj);
        }

        private void parse_route (Json.Object? lang_json_obj, LspLanguageRouter router, string json_field, LspFeatures feature) {
            if (lang_json_obj.has_member (json_field)) {
                var arr = lang_json_obj.get_array_member (json_field);
                foreach (var el in arr.get_elements ()) {
                    router.add_server_feature (feature, el.get_string ());
                }
            }
        }

        /**
         * ГЕТТЕР: Извлечение маршрутов фич для языка
         */
        public LspLanguageRouter? get_router_for_language (string language_id) {
            if (!this.merged_routing.has_member (language_id)) return null;

            var lang_json_obj = this.merged_routing.get_object_member (language_id);
            var router = new LspLanguageRouter ();

            parse_route (lang_json_obj, router, "diagnostics", LspFeatures.DIAGNOSTICS);
            parse_route (lang_json_obj, router, "completion", LspFeatures.COMPLETION);
            parse_route (lang_json_obj, router, "formatting", LspFeatures.FORMATTING);
            parse_route (lang_json_obj, router, "code_actions", LspFeatures.CODE_ACTIONS);
            parse_route (lang_json_obj, router, "definition", LspFeatures.DEFINTION);
            parse_route (lang_json_obj, router, "hover", LspFeatures.HOVER);

            return router;
        }

        /**
         * УТИЛИТА ГЛУБОКОГО СЛИЯНИЯ (Deep Merge) ДВУХ JSON-ОБЪЕКТОВ
         * Позволяет точечно переписывать ключи, строки и массивы, сохраняя структуру [INDEX]
         */
        private void deep_merge_objects (Json.Object target, Json.Object source) {
            foreach (string key in source.get_members ()) {
                var source_node = source.get_member (key);

                // Если ключа в цели не было — просто копируем его целиком [INDEX]
                if (!target.has_member (key)) {
                    target.set_member (key, source_node.copy ());
                    continue;
                }

                var target_node = target.get_member (key);

                // Если оба элемента являются JSON-объектами — спускаемся на уровень ниже (рекурсия) [INDEX]
                if (target_node.get_node_type () == Json.NodeType.OBJECT && source_node.get_node_type () == Json.NodeType.OBJECT) {
                    this.deep_merge_objects (target_node.get_object (), source_node.get_object ());
                } 
                // Во всех остальных случаях (примитивы, массивы команд) оверрайд из lsp.json полностью заменяет дефолт [INDEX]
                else {
                    target.set_member (key, source_node.copy ());
                }
            }
        }
    }
}
