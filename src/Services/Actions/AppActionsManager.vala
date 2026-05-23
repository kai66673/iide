/*
*/

public class Iide.AppActionsManager: Object {
    private static AppActionsManager? _instance;
    private GLib.Settings settings;
    private Gee.HashMap<string, Iide.AppAction> actions;
    private Gee.HashMap<string, string> shortcuts;

    public static AppActionsManager get_instance () {
        if (_instance == null) {
            _instance = new AppActionsManager ();
        }
        return _instance;
    }

    private AppActionsManager () {
        settings = SettingsService.get_instance ().settings;
        actions = new Gee.HashMap<string, Iide.AppAction> ();
        shortcuts = new Gee.HashMap<string, string> ();
        load_shortcuts_from_gsettings();
    }

    private void load_shortcuts_from_gsettings () {
        var json_str = settings.get_string ("shortcuts");
        if (json_str == null || json_str == "") {
            save_shortcuts_to_gsettings ();
            return;
        }

        try {
            var parser = new Json.Parser ();
            parser.load_from_data (json_str);
            var root = parser.get_root ();
            if (root.get_node_type () == Json.NodeType.OBJECT) {
                var obj = root.get_object ();
                obj.foreach_member ((obj, name, node) => {
                    shortcuts.set (name, node.get_string ());
                });
            }
        } catch (Error e) {
            warning ("Failed to parse shortcuts: %s", e.message);
        }
    }

    private void save_shortcuts_to_gsettings () {
        var root = new Json.Node (Json.NodeType.OBJECT);
        var obj = new Json.Object ();
        foreach (var entry in shortcuts.entries) {
            obj.set_string_member (entry.key, entry.value);
        }
        root.set_object (obj);

        var generator = new Json.Generator ();
        generator.set_root (root);
        var json_str = generator.to_data (null);
        settings.set_string ("shortcuts", json_str);
    }

    private bool get_boolean_setting_safe (string key_name, bool fallback_value) {
        if (settings.settings_schema != null && settings.settings_schema.has_key (key_name)) {
            return settings.get_boolean (key_name);
        }
        return fallback_value;
    }

    public void register_action (Gtk.Application app, Iide.AppAction action) {
        actions.set (action.id, action);
        if (shortcuts.has_key (action.id)) {
            action.set_shortcut (shortcuts.get (action.id));
        }

        if (action.is_toggle) {
            bool saved_state = get_boolean_setting_safe (action.id, true);
            action.update_state (saved_state);

            var toggle_action = new SimpleAction.stateful (
                action.id,
                null,
                new Variant.boolean (action.state)
            );
            toggle_action.activate.connect (() => {
                action.execute ();
            });
            action.state_changed.connect ((new_state) => {
                toggle_action.set_state (new Variant.boolean (new_state));
                settings.set_boolean (action.id, new_state);
            });
            app.add_action (toggle_action);
        } else {
            var simple_action = new SimpleAction (action.id, null);
            simple_action.activate.connect (() => {
                action.execute ();
            });
            app.add_action (simple_action);
        }

        if (action.shortcut != null && action.shortcut != "") {
            app.set_accels_for_action ("app." + action.id, { action.shortcut });
        }

        action.shortcut_changed.connect ((new_shortcut) => {
            if (new_shortcut != null && new_shortcut != "") {
                app.set_accels_for_action ("app." + action.id, { action.shortcut });
            } else {
                app.set_accels_for_action ("app." + action.id, {});
            }
            if (new_shortcut == null && shortcuts.has_key (action.id)) {
                shortcuts.unset (action.id);
            } else {
                shortcuts.set(action.id, new_shortcut);
            }
            save_shortcuts_to_gsettings();
        });
    }

    public void unregister_action (string action_id) {
        actions.unset (action_id);
        shortcuts.unset (action_id);
    }
}