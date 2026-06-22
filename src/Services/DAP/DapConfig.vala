/*
*/
public class Iide.DapConfig : GLib.Object {
    public string id { get; private set; }            // Например, "python-local" или "lldb-native"
    public string[] command { get; private set; }     // ["python3", "-m", "debugpy.adapter"]
    public string transport { get; private set; default = "stdio"; } // "stdio" или "tcp"

    public DapConfig (string id, Json.Object obj) {
        Object ();
        this.id = id;
        
        if (obj.has_member ("transport")) {
            this.transport = obj.get_string_member ("transport");
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