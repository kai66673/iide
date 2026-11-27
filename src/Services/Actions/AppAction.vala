/*
*/

public abstract class Iide.AppAction : Object {
    private string? _current_shortcut = null; 

    public abstract string id { get; }
    public abstract string name { get; }
    public abstract string? description { get; }
    public abstract string? icon_name { get; }
    public virtual string? category { get; default = null; }

    public abstract string? default_shortcut { get; default = null; }
    public string? shortcut { get { return _current_shortcut ?? default_shortcut; } }
    public string? current_shortcut { get { return _current_shortcut; } }
    public bool is_default_shortcut { get { return _current_shortcut == null || _current_shortcut == default_shortcut; } }

    public signal void shortcut_changed (string? new_shortcut);
    public signal void state_changed (bool new_state);

    public virtual bool is_toggle { get; default = false; }
    public virtual bool state { get; protected set; default = false; }
    
    public void set_shortcut(string? new_shortcut) {
        _current_shortcut = new_shortcut;
        shortcut_changed(shortcut);
    }

    public void update_state (bool new_state) {
        // Идемпотентность обязательна: state_changed пишет значение в GSettings,
        // а AppActionsManager слушает изменения GSettings и вызывает update_state
        // обратно — без гейта эти две цепочки замкнулись бы в цикл.
        if (state == new_state) {
            return;
        }
        state = new_state;
        state_changed (new_state);
    }

    public virtual bool can_execute () { return true; }
    public virtual void execute () {}
}
