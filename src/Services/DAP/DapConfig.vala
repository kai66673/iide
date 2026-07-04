/*
*/
public class Iide.DapConfig : GLib.Object {
    public string id { get; private set; }            // Например, "python-local" или "lldb-native"
    public string[] command { get; private set; }     // ["python3", "-m", "debugpy.adapter"]
    public string transport { get; private set; default = "stdio"; } // "stdio" или "tcp"

    // Строки паттернов регулярного выражения для Ctrl+Click навигации [INDEX]
    public string[] output_link_regex_patterns { get; private set; }

    public DapConfig (string id, Json.Object obj) {
        Object ();
        this.id = id;
        
        if (obj.has_member ("transport")) {
            this.transport = obj.get_string_member ("transport");
        }

        // Парсим массив регулярок из манифеста
        if (obj.has_member ("outputLinkRegex")) {
            string[] local_patterns = {};
            var regex_node = obj.get_member ("outputLinkRegex");
            
            if (regex_node.get_node_type () == Json.NodeType.ARRAY) {
                var arr = regex_node.get_array ();
                foreach (var element in arr.get_elements ()) {
                    local_patterns += element.get_string ();
                }
            } else if (regex_node.get_node_type () == Json.NodeType.VALUE) {
                // Фоллбэк на случай, если в конфиге осталась одиночная строка
                local_patterns += regex_node.get_string ();
            }
            this.output_link_regex_patterns = local_patterns;
        }

        // Вытаскиваем Си-массив команды запуска подпроцесса отладчика
        if (obj.has_member ("command")) {
            var cmd_array = obj.get_array_member ("command");
            string[] cmd = {};
            foreach (var element in cmd_array.get_elements ()) {
                cmd += element.get_string ();
            }
            this.command = cmd;
        } else {
            this.command = {};
        }
    }
}