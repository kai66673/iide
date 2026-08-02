/*
*/

public abstract class Iide.BasePanel : Panel.Widget {
    protected weak WindowSession session;

    private bool content_visible = false;

    public bool is_content_visible { get { return content_visible; } }

    protected BasePanel (WindowSession session, string title, string icon_name) {
        Object (title: title, icon_name: icon_name);
        this.session = session;
    }

    public void add_to_frame (Panel.Frame frame) {
        frame.add (this);
        this.content_visible = true;
    }

    public void remove_from_frame (Panel.Frame frame) {
        frame.remove (this);
        this.content_visible = false;
    }

    public void initial_add (Panel.DocumentWorkspace ws, Panel.Position? pos = null) {
        ws.add_widget (this, pos ?? this.initial_pos ());
        this.content_visible = true;
    }

    public abstract Panel.Position initial_pos ();
    public abstract string panel_id ();
}
