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

[CCode (cname = "gtk_style_context_add_provider_for_display", cheader_filename = "gtk/gtk.h")]
extern void add_provider_to_display (Gdk.Display display, Gtk.StyleProvider provider, uint priority);

public class Iide.Application : Adw.Application {
    private Iide.SettingsService settings;
    private Iide.ActionManager action_manager;
    private SimpleActionGroup simple_action_group = new SimpleActionGroup ();

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
        action_manager = Iide.ActionManager.get_instance ();

        register_builtin_actions ();
        apply_shortcuts ();
    }

    private void register_builtin_actions () {
        action_manager.register_action (new SaveAllAction (this));
        action_manager.register_action (new OpenProjectAction (this));
        action_manager.register_action (new PreferencesAction (this));
        action_manager.register_action (new ToggleMinimapAction (this));
        action_manager.register_action (new FuzzyFinderAction (this));
        action_manager.register_action (new SearchSymbolAction (this));
        action_manager.register_action (new SearchInFilesAction (this));
        action_manager.register_action (new ZoomInAction ());
        action_manager.register_action (new ZoomOutAction ());
        action_manager.register_action (new ZoomResetAction ());
        action_manager.register_action (new ExpandSelectionAction ());
        action_manager.register_action (new ShrinkSelectionAction ());
        action_manager.register_action (new QuitAction ());
        action_manager.register_action (new NavigationBackAction (this));
        action_manager.register_action (new NavigationForwardAction (this));

        // Ins/Ovr toggle
        // Действие переключения режима
        var toggle_overwrite = new SimpleAction ("toggle-overwrite", null);
        toggle_overwrite.activate.connect (() => {
            // Переключаем встроенное свойство SourceView
            var win = active_window as Iide.Window;
            if (win != null) {
                var view = win.get_active_source_view ();
                if (view != null) {
                    view.overwrite = !view.overwrite;
                }
            }
        });
        simple_action_group.add_action (toggle_overwrite);
        set_accels_for_action ("editor.toggle-overwrite", { "Insert" });
    }

    private void apply_shortcuts () {
        action_manager.apply_shortcuts_to_application (this);

        action_manager.get_all_actions ().foreach ((action) => {
            action.shortcut_changed.connect ((new_shortcut) => {
                if (new_shortcut != null && new_shortcut != "") {
                    this.set_accels_for_action ("app." + action.id, { new_shortcut });
                } else {
                    this.set_accels_for_action ("app." + action.id, {});
                }
            });
            return true;
        });
    }

    public Iide.ActionManager get_action_manager () {
        return action_manager;
    }

    public Iide.SettingsService get_settings () {
        return settings;
    }

    public void register_embedded_fonts () {
        try {
            // Путь к шрифту в GResource
            string font_path = "/org/github/kai66673/iide/fonts/SymbolsNerdFontMono-Regular.ttf";
            var bytes = resources_lookup_data (font_path, ResourceLookupFlags.NONE);

            // В GTK4 для кастомных шрифтов из памяти используется PangoCairo и FontConfig
            // На Linux/Arch самый простой способ - создать временный конфиг
            // или использовать Fontconfig напрямую.

            // Но есть способ проще для GTK4 через CSS (начиная с новых версий):
            string css = """
            @font-face {
                font-family: "Symbols Nerd Font Mono";
                src: url("resource:///org/github/kai66673/iide/fonts/SymbolsNerdFontMono-Regular.ttf");
            }
        """;
            var provider = new Gtk.CssProvider ();
            provider.load_from_bytes (new GLib.Bytes (css.data));
            add_provider_to_display (
                                     Gdk.Display.get_default (),
                                     provider,
                                     Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
            );

            message ("Встроенный шрифт Nerd Font успешно зарегистрирован через CSS.");
        } catch (Error e) {
            message ("Не удалось загрузить встроенный шрифт: %s", e.message);
        }
    }

    public override void activate () {
        base.activate ();

        var icon_theme = Gtk.IconTheme.get_for_display (Gdk.Display.get_default ());
        icon_theme.add_resource_path ("/org/github/kai66673/iide/icons");

        var css_provider = new Gtk.CssProvider ();
        css_provider.load_from_resource ("/org/github/kai66673/iide/style.css");
        add_provider_to_display (
                                 Gdk.Display.get_default (),
                                 css_provider,
                                 Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        );

        register_embedded_fonts ();

        var win = this.active_window ?? new Iide.Window (this);
        win.present ();
    }
}

private class SaveAllAction : Iide.Action {
    private weak Iide.Application app;

    public SaveAllAction (Iide.Application app) {
        this.app = app;
    }

    public override string id { get { return "save"; } }
    public override string name { get { return _("Save All"); } }
    public override string? description { get { return _("Save all open documents"); } }
    public override string? icon_name { get { return "document-save-symbolic"; } }
    public override string? category { get { return "File"; } }

    public override bool can_execute () {
        return app ? .active_window is Iide.Window;
    }

    public override void execute () {
        var win = app ? .active_window as Iide.Window;
        win?.save_modified ();
    }
}

private class OpenProjectAction : Iide.Action {
    private weak Iide.Application app;

    public OpenProjectAction (Iide.Application app) {
        this.app = app;
    }

    public override string id { get { return "open_project"; } }
    public override string name { get { return _("Open Project"); } }
    public override string? description { get { return _("Open a project folder"); } }
    public override string? icon_name { get { return "folder-open-symbolic"; } }
    public override string? category { get { return "File"; } }

    public override bool can_execute () {
        return true;
    }

    public override void execute () {
        var win = app ? .active_window as Iide.Window;
        win?.open_project_dialog ();
    }
}

private class PreferencesAction : Iide.Action {
    private weak Iide.Application app;

    public PreferencesAction (Iide.Application app) {
        this.app = app;
    }

    public override string id { get { return "preferences"; } }
    public override string name { get { return _("Preferences"); } }
    public override string? description { get { return _("Open preferences dialog"); } }
    public override string? icon_name { get { return "preferences-system-symbolic"; } }
    public override string? category { get { return "Application"; } }

    public override bool can_execute () {
        return true;
    }

    public override void execute () {
        var dialog = new Iide.PreferencesDialog ();
        dialog.set_transient_for (app ? .active_window);
        dialog.present ();
    }
}

private class ToggleMinimapAction : Iide.Action {
    private weak Iide.Application app;

    public ToggleMinimapAction (Iide.Application app) {
        this.app = app;
        this.state = Iide.SettingsService.get_instance ().show_minimap;
    }

    public override string id { get { return "toggle_minimap"; } }
    public override string name { get { return _("Toggle Minimap"); } }
    public override string? description { get { return _("Show or hide the minimap"); } }
    public override string? icon_name { get { return "view-fullscreen-symbolic"; } }
    public override string? category { get { return "View"; } }
    public override bool is_toggle { get { return true; } }

    public override bool can_execute () {
        return true;
    }

    public override void execute () {
        var settings = Iide.SettingsService.get_instance ();
        state = !state;
        settings.show_minimap = state;
        app?.minimap_changed (state);

        state_changed (state);
        Iide.ActionManager.get_instance ().set_toggle_state (id, state);
    }
}

private class ZoomInAction : Iide.Action {
    private Iide.SettingsService settings;

    public override string id { get { return "zoom_in"; } }
    public override string name { get { return _("Zoom In"); } }
    public override string? description { get { return _("Increase editor font size"); } }
    public override string? icon_name { get { return "zoom-in-symbolic"; } }
    public override string? category { get { return "View"; } }

    public override bool can_execute () {
        settings = Iide.SettingsService.get_instance ();
        return settings.editor_font_size < FontSizeHelper.MAX_ZOOM_LEVEL;
    }

    public override void execute () {
        settings = Iide.SettingsService.get_instance ();
        var app = GLib.Application.get_default () as Iide.Application;
        settings.editor_font_size++;
        app?.zoom_changed (settings.editor_font_size);
    }
}

private class ZoomOutAction : Iide.Action {
    private Iide.SettingsService settings;

    public override string id { get { return "zoom_out"; } }
    public override string name { get { return _("Zoom Out"); } }
    public override string? description { get { return _("Decrease editor font size"); } }
    public override string? icon_name { get { return "zoom-out-symbolic"; } }
    public override string? category { get { return "View"; } }

    public override bool can_execute () {
        settings = Iide.SettingsService.get_instance ();
        return settings.editor_font_size > FontSizeHelper.MIN_ZOOM_LEVEL;
    }

    public override void execute () {
        settings = Iide.SettingsService.get_instance ();
        var app = GLib.Application.get_default () as Iide.Application;
        settings.editor_font_size--;
        app?.zoom_changed (settings.editor_font_size);
    }
}

private class ZoomResetAction : Iide.Action {
    private Iide.SettingsService settings;

    public override string id { get { return "zoom_reset"; } }
    public override string name { get { return _("Zoom Reset"); } }
    public override string? description { get { return _("Reset editor font size to default"); } }
    public override string? icon_name { get { return "zoom-original-symbolic"; } }
    public override string? category { get { return "View"; } }

    public override bool can_execute () {
        return true;
    }

    public override void execute () {
        settings = Iide.SettingsService.get_instance ();
        var app = GLib.Application.get_default () as Iide.Application;
        settings.editor_font_size = FontSizeHelper.DEFAULT_ZOOM_LEVEL;
        app?.zoom_changed (settings.editor_font_size);
    }
}

private class ExpandSelectionAction : Iide.Action {
    public override string id { get { return "expand_selection"; } }
    public override string name { get { return _("Expand Selection"); } }
    public override string? description { get { return _("Expand the current selection"); } }
    public override string? icon_name { get { return "zoom-original-symbolic"; } }
    public override string? category { get { return "View"; } }

    public override bool can_execute () {
        return true;
    }

    public override void execute () {
        var app = GLib.Application.get_default () as Iide.Application;
        var win = app ? .active_window as Iide.Window;
        if (win != null) {
            win.get_active_source_view () ? .ts_highlighter ? .expand_selection ();
        }
    }
}

private class ShrinkSelectionAction : Iide.Action {
    public override string id { get { return "shrink_selection"; } }
    public override string name { get { return _("Shrink Selection"); } }
    public override string? description { get { return _("Shrink the current selection"); } }
    public override string? icon_name { get { return "zoom-original-symbolic"; } }
    public override string? category { get { return "View"; } }

    public override bool can_execute () {
        return true;
    }

    public override void execute () {
        var app = GLib.Application.get_default () as Iide.Application;
        var win = app ? .active_window as Iide.Window;
        if (win != null) {
            win.get_active_source_view () ? .ts_highlighter ? .shrink_selection ();
        }
    }
}

private class QuitAction : Iide.Action {
    public override string id { get { return "quit"; } }
    public override string name { get { return _("Quit"); } }
    public override string? description { get { return _("Quit the application"); } }
    public override string? icon_name { get { return "application-exit-symbolic"; } }
    public override string? category { get { return "Application"; } }

    public override bool can_execute () {
        return true;
    }

    public override void execute () {
        var app = GLib.Application.get_default () as Iide.Application;
        app?.quit ();
    }
}

private class FuzzyFinderAction : Iide.Action {
    private weak Iide.Application app;

    public FuzzyFinderAction (Iide.Application app) {
        this.app = app;
    }

    public override string id { get { return "fuzzy_finder"; } }
    public override string name { get { return _("Quick Open"); } }
    public override string? description { get { return _("Open a file quickly by name"); } }
    public override string? icon_name { get { return "system-search-symbolic"; } }
    public override string? category { get { return "File"; } }

    public override bool can_execute () {
        return app ? .active_window is Iide.Window;
    }

    public override void execute () {
        var win = app ? .active_window as Iide.Window;
        if (win != null) {
            var dialog = new Iide.SearchWindow (win, win.get_document_manager ());
            dialog.set_active_page ("files");
            dialog.present ();
        }
    }
}

private class SearchSymbolAction : Iide.Action {
    private weak Iide.Application app;

    public SearchSymbolAction (Iide.Application app) {
        this.app = app;
    }

    public override string id { get { return "search_symbol"; } }
    public override string name { get { return _("Search  Symbol"); } }
    public override string? description { get { return _("Search Symbol in Project"); } }
    public override string? icon_name { get { return "system-search-symbolic"; } }
    public override string? category { get { return "Edit"; } }

    public override bool can_execute () {
        return app ? .active_window is Iide.Window;
    }

    public override void execute () {
        var win = app ? .active_window as Iide.Window;
        if (win != null) {
            var dialog = new Iide.SearchWindow (win, win.get_document_manager ());
            dialog.set_active_page ("symbols");
            dialog.present ();
        }
    }
}

private class SearchInFilesAction : Iide.Action {
    private weak Iide.Application app;

    public SearchInFilesAction (Iide.Application app) {
        this.app = app;
    }

    public override string id { get { return "search_in_files"; } }
    public override string name { get { return _("Search in Files"); } }
    public override string? description { get { return _("Search for text in all project files"); } }
    public override string? icon_name { get { return "edit-find-symbolic"; } }
    public override string? category { get { return "Edit"; } }

    public override bool can_execute () {
        return app ? .active_window is Iide.Window;
    }

    public override void execute () {
        var win = app ? .active_window as Iide.Window;
        if (win != null) {
            var dialog = new Iide.SearchWindow (win, win.get_document_manager ());
            dialog.set_active_page ("text");
            dialog.present ();
        }
    }
}

private class NavigationBackAction : Iide.Action {
    private weak Iide.Application app;

    public NavigationBackAction (Iide.Application app) {
        this.app = app;
    }

    public override string id { get { return "navigation_back"; } }
    public override string name { get { return _("Navigation Back"); } }
    public override string? description { get { return _("Navigation Back"); } }
    public override string? icon_name { get { return "go-previous-symbolic"; } }
    public override string? category { get { return "Application"; } }

    public override bool can_execute () {
        return app ? .active_window is Iide.Window;
    }

    public override void execute () {
        var win = app ? .active_window as Iide.Window;
        if (win != null) {
            Iide.NavigationHistoryService.get_instance ().navigate_back ();
        }
    }
}

private class NavigationForwardAction : Iide.Action {
    private weak Iide.Application app;

    public NavigationForwardAction (Iide.Application app) {
        this.app = app;
    }

    public override string id { get { return "navigation_forward"; } }
    public override string name { get { return _("Navigation Forward"); } }
    public override string? description { get { return _("Navigation Forward"); } }
    public override string? icon_name { get { return "go-next-symbolic"; } }
    public override string? category { get { return "Application"; } }

    public override bool can_execute () {
        return app ? .active_window is Iide.Window;
    }

    public override void execute () {
        var win = app ? .active_window as Iide.Window;
        if (win != null) {
            Iide.NavigationHistoryService.get_instance ().navigate_forward ();
        }
    }
}