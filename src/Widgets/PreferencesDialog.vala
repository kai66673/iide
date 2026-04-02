/*
 * preferencesdialog.vala
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

public class Iide.PreferencesDialog : Adw.PreferencesWindow {
    private Iide.SettingsService settings;
    private Adw.StyleManager style_manager;

    private Adw.ComboRow color_scheme_row;
    private Adw.SwitchRow show_minimap_row;
    private Adw.SwitchRow show_line_numbers_row;
    private Adw.SwitchRow highlight_current_line_row;
    private Adw.SwitchRow auto_indent_row;

    public PreferencesDialog () {
        Object (modal: true, destroy_with_parent: true);
        settings = Iide.SettingsService.get_instance ();
        style_manager = Adw.StyleManager.get_default ();

        title = _("Preferences");
        set_default_size (500, 450);

        build_ui ();
    }

    private void build_ui () {
        var appearance_page = new Adw.PreferencesPage () {
            title = _("Appearance"),
            icon_name = "preferences-desktop-appearance-symbolic"
        };

        var appearance_group = new Adw.PreferencesGroup () {
            title = _("Appearance")
        };

        color_scheme_row = new Adw.ComboRow () {
            title = _("Color Scheme"),
            model = new Gtk.StringList ({ "System", "Light", "Dark" })
        };
        var scheme_index = settings.color_scheme;
        color_scheme_row.selected = (uint) scheme_index;
        color_scheme_row.notify["selected"].connect (() => {
            var scheme = (ColorScheme) color_scheme_row.selected;
            settings.color_scheme = scheme;
            style_manager.color_scheme = scheme.to_adw_color_scheme ();
        });
        appearance_group.add (color_scheme_row);
        appearance_page.add (appearance_group);

        var editor_page = new Adw.PreferencesPage () {
            title = _("Editor"),
            icon_name = "accessories-text-editor-symbolic"
        };

        var editor_group = new Adw.PreferencesGroup () {
            title = _("Editor")
        };

        show_minimap_row = new Adw.SwitchRow () {
            title = _("Show Minimap"),
            subtitle = _("Display a minimap showing the document overview")
        };
        show_minimap_row.active = settings.show_minimap;
        show_minimap_row.notify["active"].connect (() => {
            settings.show_minimap = show_minimap_row.active;
        });
        editor_group.add (show_minimap_row);

        show_line_numbers_row = new Adw.SwitchRow () {
            title = _("Show Line Numbers"),
            subtitle = _("Display line numbers on the editor gutter")
        };
        show_line_numbers_row.active = settings.show_line_numbers;
        show_line_numbers_row.notify["active"].connect (() => {
            settings.show_line_numbers = show_line_numbers_row.active;
        });
        editor_group.add (show_line_numbers_row);

        highlight_current_line_row = new Adw.SwitchRow () {
            title = _("Highlight Current Line"),
            subtitle = _("Highlight the line where the cursor is positioned")
        };
        highlight_current_line_row.active = settings.highlight_current_line;
        highlight_current_line_row.notify["active"].connect (() => {
            settings.highlight_current_line = highlight_current_line_row.active;
        });
        editor_group.add (highlight_current_line_row);

        auto_indent_row = new Adw.SwitchRow () {
            title = _("Auto Indent"),
            subtitle = _("Automatically indent new lines based on the previous line")
        };
        auto_indent_row.active = settings.auto_indent;
        auto_indent_row.notify["active"].connect (() => {
            settings.auto_indent = auto_indent_row.active;
        });
        editor_group.add (auto_indent_row);

        var sizes = FontSizeHelper.get_available_sizes ();
        var size_strings = new string[sizes.length];
        for (int i = 0; i < sizes.length; i++) {
            size_strings[i] = "%d px".printf (sizes[i]);
        }
        var font_size_model = new Gtk.StringList (size_strings);
        var current_level = settings.editor_font_size;
        if (current_level < FontSizeHelper.MIN_ZOOM_LEVEL || current_level > FontSizeHelper.MAX_ZOOM_LEVEL) {
            current_level = FontSizeHelper.DEFAULT_ZOOM_LEVEL;
        }

        var font_size_row = new Adw.ComboRow () {
            title = _("Font Size"),
            model = font_size_model,
            selected = (uint) (current_level - 1)
        };
        font_size_row.notify["selected"].connect (() => {
            settings.editor_font_size = (int) font_size_row.selected + 1;
        });
        editor_group.add (font_size_row);
        editor_page.add (editor_group);

        var projects_page = new Adw.PreferencesPage () {
            title = _("Projects"),
            icon_name = "folder-open-symbolic"
        };

        var projects_group = new Adw.PreferencesGroup () {
            title = _("Projects")
        };

        var recent_projects_row = new Adw.ActionRow () {
            title = _("Recent Projects")
        };
        var recent_projects = settings.recent_projects;
        if (recent_projects.length > 0) {
            var subtitle = string.joinv ("\n", recent_projects);
            recent_projects_row.subtitle = subtitle;
        } else {
            recent_projects_row.subtitle = _("No recent projects");
        }
        var clear_button = new Gtk.Button () {
            icon_name = "edit-clear-symbolic",
            tooltip_text = _("Clear Recent Projects")
        };
        clear_button.clicked.connect (() => {
            settings.clear_recent_projects ();
            recent_projects_row.subtitle = _("No recent projects");
        });
        recent_projects_row.add_suffix (clear_button);
        recent_projects_row.activatable_widget = clear_button;
        projects_group.add (recent_projects_row);
        projects_page.add (projects_group);

        var shortcuts_page = new Adw.PreferencesPage () {
            title = _("Shortcuts"),
            icon_name = "input-keyboard-symbolic"
        };

        var shortcuts_group = new Adw.PreferencesGroup () {
            title = _("Keyboard Shortcuts")
        };

        var action_manager = Iide.ActionManager.get_instance ();
        var actions = action_manager.get_all_actions ();

        var list_box = new Gtk.ListBox () {
            selection_mode = Gtk.SelectionMode.NONE,
            show_separators = true
        };

        var sorted_actions = new Gee.ArrayList<Iide.Action> ();
        foreach (var action in actions) {
            sorted_actions.add (action);
        }
        sorted_actions.sort ((a, b) => {
            var cat_cmp = (a.category ?? "").collate (b.category ?? "");
            if (cat_cmp != 0)return cat_cmp;
            return a.name.collate (b.name);
        });

        string? current_category = null;
        foreach (var action in sorted_actions) {
            if (action.category != current_category) {
                current_category = action.category;
                var header_row = new Gtk.ListBoxRow () {
                    selectable = false,
                    activatable = false
                };
                var header_label = new Gtk.Label (action.category ?? _("Other")) {
                    halign = Gtk.Align.START,
                    margin_top = 8,
                    margin_bottom = 4
                };
                header_label.add_css_class ("title");
                header_label.add_css_class ("dim-label");
                header_row.child = header_label;
                list_box.append (header_row);
            }
            var row = new ShortcutRow (action);
            list_box.append (row);
        }

        var scrolled = new Gtk.ScrolledWindow () {
            child = list_box,
            hexpand = true,
            vexpand = true
        };
        scrolled.set_size_request (-1, 300);
        shortcuts_group.add (scrolled);
        shortcuts_page.add (shortcuts_group);

        add (appearance_page);
        add (editor_page);
        add (projects_page);
        add (shortcuts_page);
    }
}

private class ShortcutRow : Gtk.ListBoxRow {
    private Iide.Action action;
    private Gtk.Label shortcut_label;

    public ShortcutRow (Iide.Action action) {
        this.action = action;

        var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12) {
            margin_start = 12,
            margin_end = 12,
            margin_top = 8,
            margin_bottom = 8
        };

        var info_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 2);
        var name_label = new Gtk.Label (action.name) {
            halign = Gtk.Align.START,
            hexpand = true
        };
        name_label.add_css_class ("title");
        var desc_label = new Gtk.Label (action.description ?? "") {
            halign = Gtk.Align.START,
            hexpand = true
        };
        desc_label.add_css_class ("caption");
        desc_label.add_css_class ("dim-label");
        info_box.append (name_label);
        info_box.append (desc_label);
        box.append (info_box);

        shortcut_label = new Gtk.Label (action.shortcut != null ? action.shortcut : _("None")) {
            halign = Gtk.Align.END,
            margin_start = 12
        };
        shortcut_label.add_css_class ("caption");
        shortcut_label.add_css_class ("dim-label");
        box.append (shortcut_label);

        var clear_button = new Gtk.Button () {
            icon_name = "edit-clear-symbolic",
            tooltip_text = _("Clear shortcut"),
            valign = Gtk.Align.CENTER
        };
        clear_button.clicked.connect (on_clear_clicked);
        box.append (clear_button);

        var capture_button = new Gtk.Button () {
            label = _("Change"),
            valign = Gtk.Align.CENTER
        };
        capture_button.clicked.connect (on_capture_clicked);
        box.append (capture_button);

        child = box;

        action.shortcut_changed.connect ((new_shortcut) => {
            shortcut_label.set_label (new_shortcut != null ? new_shortcut : _("None"));
        });
    }

    private void on_clear_clicked () {
        Iide.ActionManager.get_instance ().set_shortcut (action.id, null);
    }

    private void on_capture_clicked () {
        var window = this.get_ancestor (typeof (Gtk.Window)) as Gtk.Window;
        var dialog = new ShortcutCaptureWindow (action, window);
        dialog.show ();
    }
}

private class ShortcutCaptureWindow : Gtk.Window {
    private Iide.Action action;
    private Gtk.Label label;
    private uint keyval = 0;
    private Gdk.ModifierType modifiers;

    public ShortcutCaptureWindow (Iide.Action action, Gtk.Window? parent) {
        this.action = action;
        title = _("Set Shortcut for %s").printf (action.name);
        modal = true;
        if (parent != null) {
            set_transient_for (parent);
        }

        var content_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 12) {
            margin_top = 20,
            margin_bottom = 20,
            margin_start = 20,
            margin_end = 20
        };

        label = new Gtk.Label (_("Press a key combination...")) {
            halign = Gtk.Align.CENTER
        };
        content_box.append (label);

        var current = action.shortcut;
        if (current != null && current != "") {
            var hint = new Gtk.Label (_("Current: %s").printf (current)) {
                halign = Gtk.Align.CENTER
            };
            hint.add_css_class ("caption");
            hint.add_css_class ("dim-label");
            content_box.append (hint);
        }

        var event_controller = new Gtk.EventControllerKey ();
        event_controller.key_pressed.connect (on_key_pressed);
        content_box.add_controller (event_controller);

        var cancel_button = new Gtk.Button () {
            label = _("Cancel")
        };
        cancel_button.clicked.connect (() => destroy ());

        var clear_button = new Gtk.Button () {
            label = _("Clear")
        };
        clear_button.clicked.connect (() => {
            Iide.ActionManager.get_instance ().set_shortcut (action.id, null);
            destroy ();
        });

        var save_button = new Gtk.Button () {
            label = _("Save")
        };
        save_button.add_css_class ("suggested-action");
        save_button.clicked.connect (on_save);

        var button_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
        button_box.append (cancel_button);
        button_box.append (clear_button);
        button_box.append (save_button);
        button_box.halign = Gtk.Align.END;
        content_box.append (button_box);

        child = content_box;
        set_size_request (350, 120);
    }

    private bool on_key_pressed (uint keyval, uint keycode, Gdk.ModifierType state) {
        var modifiers = state & (Gdk.ModifierType.SHIFT_MASK | Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.ALT_MASK | Gdk.ModifierType.SUPER_MASK);

        if (keyval == Gdk.Key.Escape) {
            destroy ();
            return true;
        }

        if (keyval == Gdk.Key.BackSpace && modifiers == 0) {
            Iide.ActionManager.get_instance ().set_shortcut (action.id, null);
            destroy ();
            return true;
        }

        if (modifiers == 0 || (modifiers & Gdk.ModifierType.CONTROL_MASK) != 0 ||
            (modifiers & Gdk.ModifierType.SHIFT_MASK) != 0 ||
            (modifiers & Gdk.ModifierType.ALT_MASK) != 0 ||
            (modifiers & Gdk.ModifierType.SUPER_MASK) != 0) {

            if (modifiers != 0) {
                this.keyval = keyval;
                this.modifiers = modifiers;
                label.set_label (format_shortcut (keyval, modifiers));
            }
            return true;
        }
        return false;
    }

    private string format_shortcut (uint keyval, Gdk.ModifierType modifiers) {
        var accel_string = "";

        if ((modifiers & Gdk.ModifierType.CONTROL_MASK) != 0)accel_string += "<primary>";
        if ((modifiers & Gdk.ModifierType.ALT_MASK) != 0)accel_string += "<Alt>";
        if ((modifiers & Gdk.ModifierType.SHIFT_MASK) != 0)accel_string += "<Shift>";
        if ((modifiers & Gdk.ModifierType.SUPER_MASK) != 0)accel_string += "<Super>";

        var key_name = Gdk.keyval_name (keyval);
        if (key_name != null) {
            accel_string += key_name;
        }

        return accel_string;
    }

    private void on_save () {
        if (keyval != 0) {
            var shortcut = format_shortcut (keyval, modifiers);
            Iide.ActionManager.get_instance ().set_shortcut (action.id, shortcut);
        }
        destroy ();
    }
}
