public abstract class Iide.BasePanel : Panel.Widget {
    protected BasePanel (string title, string icon_name) {
        Object (title: title, icon_name: icon_name);
    }

    public abstract Panel.Position initial_pos ();
    public abstract string panel_id ();
}
