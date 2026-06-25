/*
*/

public abstract class Iide.BasePanel : Panel.Widget {
    protected weak Window window;

    protected BasePanel (Window window, string title, string icon_name) {
        Object (title: title, icon_name: icon_name);
        this.window = window;
    }

    public abstract Panel.Position initial_pos ();
    public abstract string panel_id ();
}
