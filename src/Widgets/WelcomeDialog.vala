/*
 * WelcomeDialog.vala
 *
 * Окно приветствия при первом запуске.
 * Предлагает пользователю выбрать или создать проект.
 * Является Gtk.Window, чтобы не зависеть от родительского окна.
 */
using Gtk;
using Adw;

public class Iide.WelcomeDialog : Gtk.ApplicationWindow {
    public signal void project_selected (GLib.File project_root);

    public WelcomeDialog (Gtk.Application app) {
        Object (
            application: app,
            title: _("Welcome to iide"),
            default_width: 500,
            default_height: 300,
            deletable: true,
            resizable: false,
            modal: false
        );
    }

    construct {
        var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 24) {
            halign = Gtk.Align.CENTER,
            valign = Gtk.Align.CENTER,
            margin_top = 48,
            margin_bottom = 48,
            margin_start = 48,
            margin_end = 48
        };

        var title_label = new Gtk.Label (_("Welcome to iide")) {
            wrap = true
        };
        title_label.add_css_class ("title-1");

        var subtitle_label = new Gtk.Label (_("Open an existing project or create a new one to get started.")) {
            wrap = true
        };
        subtitle_label.add_css_class ("dim-label");

        var open_btn = new Gtk.Button.with_label (_("Open Project")) {
            halign = Gtk.Align.CENTER
        };
        open_btn.add_css_class ("suggested-action");
        open_btn.add_css_class ("pill");
        open_btn.width_request = 200;

        var new_btn = new Gtk.Button.with_label (_("New Project")) {
            halign = Gtk.Align.CENTER
        };
        new_btn.add_css_class ("pill");
        new_btn.width_request = 200;

        box.append (title_label);
        box.append (subtitle_label);
        box.append (open_btn);
        box.append (new_btn);

        this.child = box;

        open_btn.clicked.connect (on_open_project);
        new_btn.clicked.connect (on_new_project);
    }

    private void on_open_project () {
        var dialog = new Gtk.FileDialog () {
            title = _("Open Project"),
            modal = true
        };

        var settings = Iide.SettingsService.get_instance ();
        var last_dir = settings.last_open_directory;
        if (last_dir != null && last_dir != "") {
            dialog.initial_folder = GLib.File.new_for_path (last_dir);
        }

        dialog.select_folder.begin (this, null, (obj, res) => {
            try {
                var folder = dialog.select_folder.end (res);
                if (folder != null) {
                    project_selected (folder);
                }
            } catch (Error e) {
                // User dismissed — do nothing
            }
        });
    }

    private void on_new_project () {
        var dialog = new Gtk.FileDialog () {
            title = _("Select Parent Directory"),
            modal = true
        };

        var settings = Iide.SettingsService.get_instance ();
        var last_dir = settings.last_open_directory;
        if (last_dir != null && last_dir != "") {
            dialog.initial_folder = GLib.File.new_for_path (last_dir);
        } else {
            dialog.initial_folder = GLib.File.new_for_path (Environment.get_home_dir ());
        }

        dialog.select_folder.begin (this, null, (obj, res) => {
            try {
                var parent_folder = dialog.select_folder.end (res);
                if (parent_folder != null) {
                    show_name_entry (parent_folder);
                }
            } catch (Error e) {
                // User dismissed
            }
        });
    }

    private void show_name_entry (GLib.File parent_folder) {
        var name_dialog = new Adw.AlertDialog (
            _("New Project"),
            _("Enter a name for the new project")
        );

        name_dialog.add_response ("cancel", _("Cancel"));
        name_dialog.add_response ("create", _("Create"));
        name_dialog.set_response_appearance ("create", Adw.ResponseAppearance.SUGGESTED);
        name_dialog.set_default_response ("create");
        name_dialog.set_close_response ("cancel");

        var entry = new Gtk.Entry () {
            placeholder_text = _("Project Name"),
            halign = Gtk.Align.CENTER,
            margin_top = 12
        };
        entry.width_chars = 30;
        name_dialog.set_extra_child (entry);

        name_dialog.response.connect ((response) => {
            if (response == "create") {
                string name = entry.text.strip ();
                if (name == "") return;

                var project_dir = parent_folder.get_child (name);
                try {
                    project_dir.make_directory (null);
                } catch (Error e) {
                    // Directory might already exist — that's OK
                }

                project_selected (project_dir);
            }
        });

        name_dialog.present (this);
    }
}
