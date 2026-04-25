public class Iide.ShortcutSettings : Object {
    private static ShortcutSettings? _instance;
    private GLib.Settings settings;
    private Gee.HashMap<string, string> shortcuts_cache;
    private Gee.HashMap<string, bool> toggle_states_cache;

    public static ShortcutSettings get_instance () {
        if (_instance == null) {
            _instance = new ShortcutSettings ();
        }
        return _instance;
    }

    private ShortcutSettings () {
        settings = new GLib.Settings ("org.github.kai66673.iide");
        shortcuts_cache = new Gee.HashMap<string, string> ();
        toggle_states_cache = new Gee.HashMap<string, bool> ();
        set_default_shortcuts ();
        set_default_toggle_states ();
        load_from_gsettings ();
    }

    private void set_default_shortcuts () {
        shortcuts_cache.set ("save", "<primary>s");
        shortcuts_cache.set ("open_project", "<primary>o");
        shortcuts_cache.set ("preferences", "<primary>comma");
        shortcuts_cache.set ("toggle_minimap", "<primary>m");
        shortcuts_cache.set ("fuzzy_finder", "<primary>p");
        shortcuts_cache.set ("search_symbol", "<primary>t");
        shortcuts_cache.set ("search_in_files", "<primary><shift>f");
        shortcuts_cache.set ("zoom_in", "<primary>plus");
        shortcuts_cache.set ("zoom_out", "<primary>minus");
        shortcuts_cache.set ("zoom_reset", "<primary>0");
        shortcuts_cache.set ("expand_selection", "<primary>w");
        shortcuts_cache.set ("shrink_selection", "<primary><shift>w");
        shortcuts_cache.set ("quit", "<primary>q");
    }

    private void set_default_toggle_states () {
        toggle_states_cache.set ("toggle_minimap", true);
    }

    private void load_from_gsettings () {
        var json_str = settings.get_string ("shortcuts");
        if (json_str == null || json_str == "") {
            save_to_gsettings ();
            return;
        }

        try {
            var parser = new Json.Parser ();
            parser.load_from_data (json_str);
            var root = parser.get_root ();
            if (root.get_node_type () == Json.NodeType.OBJECT) {
                var obj = root.get_object ();
                obj.foreach_member ((obj, name, node) => {
                    shortcuts_cache.set (name, node.get_string ());
                });
            }
        } catch (Error e) {
            warning ("Failed to parse shortcuts: %s", e.message);
        }
    }

    private void save_to_gsettings () {
        var root = new Json.Node (Json.NodeType.OBJECT);
        var obj = new Json.Object ();
        foreach (var entry in shortcuts_cache.entries) {
            obj.set_string_member (entry.key, entry.value);
        }
        root.set_object (obj);

        var generator = new Json.Generator ();
        generator.set_root (root);
        var json_str = generator.to_data (null);
        settings.set_string ("shortcuts", json_str);
    }

    public signal void shortcut_changed (string action_id, string? new_shortcut);

    public string ? get_shortcut (string action_id) {
        return shortcuts_cache.get (action_id);
    }

    public void set_shortcut (string action_id, string? shortcut) {
        if (shortcut == null || shortcut == "") {
            shortcuts_cache.unset (action_id);
        } else {
            shortcuts_cache.set (action_id, shortcut);
        }
        save_to_gsettings ();
        shortcut_changed (action_id, shortcut);
    }

    public Gee.Map<string, string?> get_all_shortcuts () {
        var result = new Gee.HashMap<string, string?> ();
        foreach (var entry in shortcuts_cache.entries) {
            result.set (entry.key, entry.value);
        }
        return result;
    }

    public void reset_shortcut (string action_id) {
        shortcuts_cache.unset (action_id);
        save_to_gsettings ();
        shortcut_changed (action_id, null);
    }

    public void reset_all_shortcuts () {
        shortcuts_cache.clear ();
        save_to_gsettings ();
        foreach (var action_id in shortcuts_cache.keys) {
            shortcut_changed (action_id, null);
        }
    }

    public bool get_toggle_state (string action_id) {
        return toggle_states_cache.get (action_id);
    }

    public void set_toggle_state (string action_id, bool state) {
        toggle_states_cache.set (action_id, state);
    }
}