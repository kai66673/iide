public abstract class Iide.Action : Object {
    public abstract string id { get; }
    public abstract string name { get; }
    public abstract string? description { get; }
    public abstract string? icon_name { get; }
    public string? shortcut { get; set; }

    public signal void shortcut_changed (string? new_shortcut);
    public signal void state_changed (bool new_state);

    public virtual bool is_toggle { get; default = false; }
    public virtual bool state { get; protected set; default = false; }

    public void update_state (bool new_state) {
        state = new_state;
        state_changed (new_state);
    }

    public abstract bool can_execute ();
    public abstract void execute ();

    public virtual string? category { get; default = null; }
}