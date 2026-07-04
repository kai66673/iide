/*
*/
public class Iide.DapVariable : GLib.Object {
    public string name { get; private set; }
    public string value_str { get; private set; }
    public string type_label { get; private set; }
    public int variables_reference { get; private set; } // Если > 0, объект можно раскрыть!
    
    // Список дочерних объектов
    public Gee.ArrayList<DapVariable>? children { get; set; default = null; }
    public bool children_fetched { get; set; default = false; }

    public DapVariable (string name, string val, string type, int reference) {
        Object ();
        this.name = name;
        this.value_str = val;
        this.type_label = type;
        this.variables_reference = reference;

        if (this.variables_reference > 0) {
            this.children = new Gee.ArrayList<DapVariable> ();
        }
    }
    
    public bool is_expandable () {
        return this.variables_reference > 0;
    }
}