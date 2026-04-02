public class Iide.ActionManager : Object {
    private static ActionManager? _instance;
    private Gee.HashMap<string, Iide.Action> actions;
    private Gee.HashMap<string, string> shortcuts;
    private Iide.ShortcutSettings shortcut_settings;

    public static ActionManager get_instance () {
        if (_instance == null) {
            _instance = new ActionManager ();
        }
        return _instance;
    }

    private ActionManager () {
        actions = new Gee.HashMap<string, Iide.Action> ();
        shortcuts = new Gee.HashMap<string, string> ();
        shortcut_settings = Iide.ShortcutSettings.get_instance ();
        shortcut_settings.shortcut_changed.connect (on_shortcut_changed);
    }

    public void register_action (Iide.Action action) {
        actions.set (action.id, action);
        var saved_shortcut = shortcut_settings.get_shortcut (action.id);
        action.shortcut = saved_shortcut;
        shortcuts.set (action.id, saved_shortcut);

        if (action.is_toggle) {
            var saved_state = shortcut_settings.get_toggle_state (action.id);
            action.update_state (saved_state);
        }
    }

    public void unregister_action (string action_id) {
        actions.unset (action_id);
        shortcuts.unset (action_id);
    }

    public Iide.Action? get_action (string action_id) {
        return actions.get (action_id);
    }

    public Gee.Collection<Iide.Action> get_all_actions () {
        return actions.values;
    }

    public Gee.ArrayList<Iide.Action> get_actions_by_category (string category) {
        var result = new Gee.ArrayList<Iide.Action> ();
        foreach (var action in actions.values) {
            if (action.category == category) {
                result.add (action);
            }
        }
        return result;
    }

    public void execute (string action_id) {
        var action = actions.get (action_id);
        if (action != null && action.can_execute ()) {
            action.execute ();
        }
    }

    public bool can_execute (string action_id) {
        var action = actions.get (action_id);
        return action != null && action.can_execute ();
    }

    public string? get_shortcut (string action_id) {
        return shortcuts.get (action_id);
    }

    public void set_shortcut (string action_id, string? shortcut) {
        var action = actions.get (action_id);
        if (action != null) {
            action.shortcut = shortcut;
            shortcuts.set (action_id, shortcut);
            shortcut_settings.set_shortcut (action_id, shortcut);
            action.shortcut_changed (shortcut);
        }
    }

    public void set_toggle_state (string action_id, bool state) {
        var action = actions.get (action_id);
        if (action != null && action.is_toggle) {
            action.update_state (state);
            shortcut_settings.set_toggle_state (action_id, state);
        }
    }

    private void on_shortcut_changed (string action_id, string? new_shortcut) {
        var action = actions.get (action_id);
        if (action != null) {
            action.shortcut = new_shortcut;
            shortcuts.set (action_id, new_shortcut);
            action.shortcut_changed (new_shortcut);
        }
    }

    public void apply_shortcuts_to_application (Gtk.Application app) {
        foreach (var action in actions.values) {
            if (action.is_toggle) {
                var toggle_action = new SimpleAction.stateful (
                    action.id,
                    null,
                    new Variant.boolean (action.state)
                );
                toggle_action.activate.connect (() => {
                    execute (action.id);
                });
                action.state_changed.connect ((new_state) => {
                    toggle_action.set_state (new Variant.boolean (new_state));
                });
                app.add_action (toggle_action);
            } else {
                var simple_action = new SimpleAction (action.id, null);
                simple_action.activate.connect (() => {
                    execute (action.id);
                });
                app.add_action (simple_action);
            }

            if (action.shortcut != null && action.shortcut != "") {
                app.set_accels_for_action ("app." + action.id, { action.shortcut });
            }
        }
    }
}