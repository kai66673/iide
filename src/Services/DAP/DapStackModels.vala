/*
*/
namespace Iide {
    /**
     * СТЕРИЛЬНАЯ МОДЕЛЬ ПОТОКА ОС
     */
    public class DapThread : GLib.Object {
        public int id { get; private set; }
        public string name { get; private set; }
        public bool stack_fetched { get; set; default = false; }
        public Gee.ArrayList<DapStackFrame> frames { get; private set; }

        public DapThread (int id, string name) {
            Object ();
            this.id = id;
            this.name = name;
            this.frames = new Gee.ArrayList<DapStackFrame> ();
        }
    }

    /**
     * СТЕРИЛЬНАЯ МОДЕЛЬ КАДРА СТЕКА (ФУНКЦИИ)
     */
    public class DapStackFrame : GLib.Object {
        public int id { get; private set; } // frameId для scopes/variables [INDEX]
        public string function_name { get; private set; } // например, "main" или "calculate"
        public string file_uri { get; private set; }
        public int line { get; private set; } // 0-indexed для GTK редактора

        public DapStackFrame (int id, string func_name, string uri, int line) {
            Object ();
            this.id = id;
            this.function_name = func_name;
            this.file_uri = uri;
            this.line = line;
        }
    }
}
