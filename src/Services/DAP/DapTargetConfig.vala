/*
*/
public class Iide.DapTargetConfig : GLib.Object {
    public string name { get; set; }
    public string adapter_id { get; set; }
    public Json.Object raw_object { get; private set; }

    public DapTargetConfig (Json.Object obj) {
        Object ();
        this.raw_object = obj;
        this.name = obj.has_member ("name") ? obj.get_string_member ("name") : "Unnamed Target";
        this.adapter_id = obj.has_member ("adapter_id") ? obj.get_string_member ("adapter_id") : "unknown";
    }

    /**
     * УHИВEРСАЛЬHАЯ РEКУРСИВHАЯ ПОДСТАHОВКА МАКРОСОВ
     * Берет абстрактный JSON цели, очищает от служебных полей IIDE 
     * и разворачивает макросы в путях любой вложенности! [INDEX]
     */
    public Json.Object get_processed_launch_params (string current_file_path, string workspace_root_path) {
        var clean_file_path = current_file_path.replace ("file://", "");
        var clean_workspace_path = workspace_root_path.replace ("file://", "");

        var processed_root = new Json.Object ();

        // Перебираем все члены абстрактного JSON-объекта пользователя [INDEX]
        foreach (var member in this.raw_object.get_members ()) {
            // Игнорируем внутренние маркеры маршрутизации IIDE
            if (member == "name" || member == "adapter_id") continue;

            var node = this.raw_object.get_member (member);
            
            // Рекурсивно обрабатываем узел и вставляем в итоговый пакет launch [INDEX]
            processed_root.set_member (member, this.process_json_node_recursive (node, clean_file_path, clean_workspace_path));
        }

        return processed_root;
    }

    /**
     * ГЛУБОКИЙ РEКУРСИВHЫЙ ОБХОД УЗЛОВ JSON [INDEX]
     */
    private Json.Node process_json_node_recursive (Json.Node node, string file_path, string workspace_path) {
        var result_node = new Json.Node (node.get_node_type ());

        switch (node.get_node_type ()) {
            // Если нашли строку — подставляем макросы путей! [INDEX]
            case Json.NodeType.VALUE:
                var gvalue = node.get_value ();
                if (gvalue.holds (typeof (string))) {
                    string val = node.get_string ();
                    
                    // Проверяем, содержит ли строка макросы путей воркспейса
                    bool contains_macro = val.contains ("${file}") || val.contains ("${workspace_root}");

                    // Выполняем базовую подстановку макросов
                    val = val.replace ("${file}", file_path);
                    val = val.replace ("${workspace_root}", workspace_path);
                    val = val.replace ("file://", ""); // Очищаем от протоколов [INDEX]

                    // ===================================================================
                    // УМНАЯ СШИВКА PYTHONPATH С ДВОEТОЧИЯМИ
                    // Если строка содержит ':' и похожа на список путей (есть '/'),
                    // расщепляем и канонизируем каждый элемент изолированно!
                    // ===================================================================
                    if (val.contains (":") && val.contains ("/")) {
                        string[] path_chunks = val.split (":");
                        string[] canonical_chunks = {};

                        foreach (var chunk in path_chunks) {
                            string clean_chunk = chunk.strip ();
                            if (clean_chunk != "") {
                                var file_helper = GLib.File.new_for_path (clean_chunk);
                                string canonical_path = file_helper.get_path ();
                                
                                if (canonical_path != null && canonical_path != "") {
                                    canonical_chunks += canonical_path;
                                } else {
                                    canonical_chunks += clean_chunk; // Фоллбэк, если GIO не справился
                                }
                            }
                        }
                        // Склеиваем обратно через двоеточие!
                        val = string.joinv (":", canonical_chunks);
                    }
                    // Oдиночный путь (Ваша рабочая эвристика для одиночных строк program/cwd)
                    else if (contains_macro || val.has_prefix ("/")) {
                        var file_helper = GLib.File.new_for_path (val);
                        string canonical_path = file_helper.get_path ();
                        if (canonical_path != null && canonical_path != "") {
                            val = canonical_path;
                        }
                    }

                    result_node.set_string (val);
                } else {
                    result_node.set_value (gvalue);
                }
                break;

            // Если нашли вложенный объект (например, словарь "env" или настройки "launch") — уходим на глубину! [INDEX]
            case Json.NodeType.OBJECT:
                var src_obj = node.get_object ();
                var dest_obj = new Json.Object ();
                
                foreach (var member in src_obj.get_members ()) {
                    var child_node = src_obj.get_member (member);
                    dest_obj.set_member (member, this.process_json_node_recursive (child_node, file_path, workspace_path));
                }
                result_node.set_object (dest_obj);
                break;

            // If нашли массив (например, "args" или "initCommands") — обрабатываем каждый элемент! [INDEX]
            case Json.NodeType.ARRAY:
                var src_arr = node.get_array ();
                var dest_arr = new Json.Array ();
                
                foreach (var element_node in src_arr.get_elements ()) {
                    dest_arr.add_element (this.process_json_node_recursive (element_node, file_path, workspace_path));
                }
                result_node.set_array (dest_arr);
                break;

            default:
                // Null или примитивы копируем как есть
                result_node = node;
                break;
        }

        return result_node;
    }
}
