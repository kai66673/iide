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
    public Application () {
        Object (
                application_id: "org.github.kai66673.iide",
                flags: ApplicationFlags.DEFAULT_FLAGS,
                resource_base_path: "/org/github/kai66673/iide"
        );
    }

    construct {
        ActionEntry[] action_entries = {
            { "about", this.on_about_action },
            { "preferences", this.on_preferences_action },
            { "save", this.on_save_action },
            { "open_project", this.on_open_project_action },
            { "quit", this.quit }
        };
        this.add_action_entries (action_entries, this);
        this.set_accels_for_action ("app.quit", { "<control>q" });
        this.set_accels_for_action ("app.preferences", { "<control>comma" });
        this.set_accels_for_action ("app.save", { "<control>s" });
        this.set_accels_for_action ("app.open_project", { "<control>o" });
    }

    public override void activate () {
        base.activate ();

        var icon_theme = Gtk.IconTheme.get_for_display (Gdk.Display.get_default ());
        icon_theme.add_resource_path ("/org/github/kai66673/iide/icons");

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
        message ("app.preferences action activated");
    }

    private void on_save_action () {
        var win = active_window as Iide.Window;
        win?.save_modified ();
    }

    private void on_open_project_action () {
        var win = active_window as Iide.Window;
        win?.open_project_dialog ();
    }
}
