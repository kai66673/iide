/* application.vala
 *
 * Copyright 2026 kai
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

public class Iide.Application : Adw.Application {
    private Iide.SettingsService settings;

    public signal void zoom_changed (int zoom_level);
    public signal void minimap_changed (bool visible);

    public Application () {
        Object (
                application_id: "org.github.kai66673.iide",
                flags: ApplicationFlags.DEFAULT_FLAGS,
                resource_base_path: "/org/github/kai66673/iide"
        );
    }

    construct {
        settings = Iide.SettingsService.get_instance ();

        ActionEntry[] action_entries = {
            { "about", this.on_about_action },
            { "preferences", this.on_preferences_action },
            { "save", this.on_save_action },
            { "open_project", this.on_open_project_action },
            { "zoom_in", this.on_zoom_in_action },
            { "zoom_out", this.on_zoom_out_action },
            { "zoom_reset", this.on_zoom_reset_action },
            { "quit", this.on_quit_action }
        };
        this.add_action_entries (action_entries, this);

        var toggle_minimap = new SimpleAction.stateful (
            "toggle_minimap",
            null,
            new Variant.boolean (settings.show_minimap)
        );
        toggle_minimap.activate.connect (() => {
            var new_state = !toggle_minimap.get_state ().get_boolean ();
            toggle_minimap.set_state (new Variant.boolean (new_state));
            settings.show_minimap = new_state;
            minimap_changed (new_state);
        });
        this.add_action (toggle_minimap);

        this.set_accels_for_action ("app.quit", { "<primary>q" });
        this.set_accels_for_action ("app.preferences", { "<primary>comma" });
        this.set_accels_for_action ("app.save", { "<primary>s" });
        this.set_accels_for_action ("app.open_project", { "<primary>o" });
        this.set_accels_for_action ("app.toggle_minimap", { "<primary>m" });
        this.set_accels_for_action ("app.zoom_in", { "<primary>plus", "<primary>equal" });
        this.set_accels_for_action ("app.zoom_out", { "<primary>minus" });
        this.set_accels_for_action ("app.zoom_reset", { "<primary>0" });
    }

    public Iide.SettingsService get_settings () {
        return settings;
    }

    public override void activate () {
        base.activate ();

        var icon_theme = Gtk.IconTheme.get_for_display (Gdk.Display.get_default ());
        icon_theme.add_resource_path ("/org/github/kai66673/iide/icons");

        var css_provider = new Gtk.CssProvider ();
        css_provider.load_from_resource ("/org/github/kai66673/iide/style.css");
        Gtk.StyleContext.add_provider_for_display (
            Gdk.Display.get_default (),
            css_provider,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        );

        var win = this.active_window ?? new Iide.Window (this);
        win.present ();
    }

    private void on_about_action () {
        string[] developers = { "kai" };
        var about = new Adw.AboutDialog () {
            application_name = "iide",
            application_icon = "org.github.kai66673.iide",
            developer_name = "kai",
            translator_credits = _("translator-credits"),
            version = "0.1.0",
            developers = developers,
            copyright = "© 2026 kai",
        };

        about.present (this.active_window);
    }

    private void on_preferences_action () {
        var dialog = new Iide.PreferencesDialog ();
        dialog.set_transient_for (this.active_window);
        dialog.present ();
    }

    private void on_save_action () {
        var win = active_window as Iide.Window;
        win?.save_modified ();
    }

    private void on_open_project_action () {
        var win = active_window as Iide.Window;
        win?.open_project_dialog ();
    }

    private void on_zoom_in_action () {
        if (settings.editor_font_size < FontSizeHelper.MAX_ZOOM_LEVEL) {
            settings.editor_font_size++;
            zoom_changed (settings.editor_font_size);
        }
    }

    private void on_zoom_out_action () {
        if (settings.editor_font_size > FontSizeHelper.MIN_ZOOM_LEVEL) {
            settings.editor_font_size--;
            zoom_changed (settings.editor_font_size);
        }
    }

    private void on_zoom_reset_action () {
        settings.editor_font_size = FontSizeHelper.DEFAULT_ZOOM_LEVEL;
        zoom_changed (settings.editor_font_size);
    }

    private void on_quit_action () {
        var win = this.active_window;
        if (win != null) {
            win.close ();
        }
    }
}
