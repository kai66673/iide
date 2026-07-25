/*
*/

public abstract class Iide.BasePanel : Panel.Widget {
    protected weak WindowSession session;

    protected BasePanel (WindowSession session, string title, string icon_name) {
        Object (title: title, icon_name: icon_name);
        this.session = session;
    }

    public abstract Panel.Position initial_pos ();
    public abstract string panel_id ();
}
