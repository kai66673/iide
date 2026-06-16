using GLib;
using Json;

namespace Iide {

    public class LspConfig : GLib.Object {
        public string[] command { get; set; }
        public bool capability_formatting { get; set; default = true; }
        public bool capability_hover { get; set; default = true; }
        public bool capability_completion { get; set; default = true; }

        // Полный шаблон инициализации из JSON
        public Json.Object? initialize_template { get; set; default = null; }
        // Словарь настроек для конкретных секций
        public Json.Object? section_settings { get; set; default = null; }

        // 1. Полностью динамическое формирование initialize_params из шаблона JSON
        public Json.Node initialize_params (string? workspace_root) {
            var root_uri = workspace_root ?? "file:///";

            if (this.initialize_template == null) {
                // Возврат пустой ноды, если шаблон не настроен
                return new Json.Node (Json.NodeType.OBJECT);
            }

            // Переводим объект шаблона в строку
            var generator = new Json.Generator ();
            var node = new Json.Node (Json.NodeType.OBJECT);
            node.set_object (this.initialize_template);
            generator.set_root (node);
            string template_str = generator.to_data (null);

            // Динамически заменяем макрос пути во всем JSON-документе инициализации
            string processed_json = template_str.replace ("${WORKSPACE_ROOT}", root_uri);

            // Парсим обратно в Json.Node
            var parser = new Json.Parser ();
            try {
                parser.load_from_data (processed_json, -1);
                return parser.get_root ().copy ();
            } catch (GLib.Error e) {
                LoggerService.get_instance ().error ("LSP", "Failed to process dynamic initialize_template: %s".printf (e.message));
                return new Json.Node (Json.NodeType.NULL);
            }
        }

        // 2. Полностью динамический ответ на "workspace/configuration" на основе значения "section"
        public Json.Node? handle_workspace_configuration (Json.Object response) {
            string method = response.has_member ("method") ? response.get_string_member ("method") : "";
            if (method != "workspace/configuration") {
                return new Json.Node (Json.NodeType.NULL);
            }

            var results = new Json.Array ();

            // Проверяем наличие параметров запроса от сервера
            if (!response.has_member ("params")) {
                var empty_node = new Json.Node (Json.NodeType.ARRAY);
                empty_node.set_array (results);
                return empty_node;
            }

            var params_obj = response.get_object_member ("params");
            if (!params_obj.has_member ("items")) {
                var empty_node = new Json.Node (Json.NodeType.ARRAY);
                empty_node.set_array (results);
                return empty_node;
            }

            var items = params_obj.get_array_member ("items");

            // Перебираем элементы, которые запросил сервер
            foreach (var item in items.get_elements ()) {
                var item_obj = item.get_object ();
                string section = item_obj.has_member ("section") ? item_obj.get_string_member ("section") : "";

                // Создаем дефолтный пустой объект ответа на случай, если секция не найдена
                var response_settings = new Json.Object ();

                // ИЩЕМ СЕКЦИЮ ДИНАМИЧЕСКИ: Если в section_settings прописан этот ключ — отдаем его содержимое
                if (this.section_settings != null && this.section_settings.has_member (section)) {
                    var target_node = this.section_settings.get_member (section);
                    if (target_node.get_node_type () == Json.NodeType.OBJECT) {
                        // Клонируем объект настроек секции напрямую из нашей конфигурационной матрицы
                        response_settings = target_node.copy ().get_object ();
                    }
                } else {
                    LoggerService.get_instance ().warning ("LSP", "Server requested unknown configuration section: '%s'. Returning empty object.".printf (section));
                }

                results.add_object_element (response_settings);
            }

            var results_node = new Json.Node (Json.NodeType.ARRAY);
            results_node.set_array (results);
            return results_node;
        }

        public static LspConfig from_json (Json.Object obj) {
            var config = new LspConfig ();
            
            // Читаем массив команды
            if (obj.has_member ("command")) {
                var cmd_array = obj.get_array_member ("command");
                var cmd_list = new Gee.ArrayList<string> ();
                foreach (var el in cmd_array.get_elements ()) {
                    cmd_list.add (el.get_string ());
                }
                config.command = cmd_list.to_array ();
            }

            // Читаем кастомные возможности (capabilities)
            if (obj.has_member ("capability_formatting"))
                config.capability_formatting = obj.get_boolean_member ("capability_formatting");
            if (obj.has_member ("capability_hover"))
                config.capability_hover = obj.get_boolean_member ("capability_hover");
            if (obj.has_member ("capability_completion"))
                config.capability_completion = obj.get_boolean_member ("capability_completion");

            // Копируем сложные JSON-объекты настроек напрямую в свойства [INDEX]
            if (obj.has_member ("initialize_template"))
                config.initialize_template = obj.dup_member ("initialize_template").get_object ();
            if (obj.has_member ("section_settings"))
                config.section_settings = obj.dup_member ("section_settings").get_object ();

            return config;
        }
    }
}
