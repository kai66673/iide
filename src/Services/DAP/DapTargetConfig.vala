/*
*/
public class Iide.DapTargetConfig : GLib.Object {
    public string name { get; set; }
    public string adapter_id { get; set; }
    public string request { get; set; }
    public string program { get; set; }
    
    // НOВЫE ПОЛЯ: Опциональная рабочая директория
    public string? cwd { get; set; default = null; }

    public Gee.ArrayList<string> args { get; private set; }
    
    // НOВЫE ПОЛЯ: Изолированный словарь переменных окружения конкретной цели [INDEX]
    public Gee.HashMap<string, string> env { get; private set; }

    // Сырой слепок исходного JSON для сохранения кастомных опций
    public Json.Object raw_object { get; private set; }

    public DapTargetConfig (Json.Object obj) {
        Object ();
        this.raw_object = obj;
        this.args = new Gee.ArrayList<string> ();
        this.env = new Gee.HashMap<string, string> ();

        this.name = obj.has_member ("name") ? obj.get_string_member ("name") : "Unnamed Target";
        this.adapter_id = obj.has_member ("adapter_id") ? obj.get_string_member ("adapter_id") : "unknown";
        this.request = obj.has_member ("request") ? obj.get_string_member ("request") : "launch";
        this.program = obj.has_member ("program") ? obj.get_string_member ("program") : "";
        
        // Парсим cwd, если он явно передан пользователем
        if (obj.has_member ("cwd")) {
            this.cwd = obj.get_string_member ("cwd");
        }

        // Парсим массив аргументов
        if (obj.has_member ("args")) {
            var args_array = obj.get_array_member ("args");
            foreach (var element in args_array.get_elements ()) {
                this.args.add (element.get_string ());
            }
        }

        // ===================================================================
        // ПАРСИНГ ПEРEМEННЫХ ОКРУЖEНИЯ ЦEЛИ (env) [INDEX]
        // ===================================================================
        if (obj.has_member ("env")) {
            var env_obj = obj.get_object_member ("env");
            foreach (var member_key in env_obj.get_members ()) {
                this.env.set (member_key, env_obj.get_string_member (member_key));
            }
        }
    }

    /**
     * ГEНEРАЦИЯ ПАРАМEТРOВ ДЛЯ ЗАПРОСА LAUNCH/ATTACH С ПОДСТАНOВКOЙ МАКРOСOВ
     */
    public Json.Object get_processed_launch_params (string current_file_path, string workspace_root_path) {
        var result = new Json.Object ();
        
        // Если cwd не был передан в JSON, по умолчанию выставляем корень воркспейса
        string calculated_cwd = this.cwd ?? "${workspace_root}";
        calculated_cwd = calculated_cwd.replace ("${workspace_root}", workspace_root_path);
        calculated_cwd = calculated_cwd.replace ("${file}", current_file_path);

        foreach (var member in this.raw_object.get_members ()) {
            // Пропускаем служебные поля IDE
            if (member == "name" || member == "adapter_id" || member == "env" || member == "cwd") continue;

            var node = this.raw_object.get_member (member);
            if (node.get_node_type () == Json.NodeType.VALUE) {
                string val = node.get_string ();
                val = val.replace ("${file}", current_file_path);
                val = val.replace ("${workspace_root}", workspace_root_path);
                result.set_string_member (member, val);
            } else {
                result.set_member (member, node);
            }
        }

        // Накатываем вычисленный и очищенный от макросов cwd в параметры DAP
        result.set_string_member ("cwd", calculated_cwd);

        // ===================================================================
        // СБOРКА И ПОДСТАНОВКА МАКРOСOВ ВНУТРИ СЛOВАРЯ env [INDEX]
        // Протокол DAP ожидает, что переменные прилетят в виде JSON-объекта
        // ===================================================================
        var processed_env_obj = new Json.Object ();
        foreach (var entry in this.env.entries) {
            string env_value = entry.value;
            env_value = env_value.replace ("${file}", current_file_path);
            env_value = env_value.replace ("${workspace_root}", workspace_root_path);
            
            processed_env_obj.set_string_member (entry.key, env_value);
        }
        
        // Скармливаем готовый словарь в параметры запроса
        result.set_object_member ("env", processed_env_obj);

        return result;
    }
}