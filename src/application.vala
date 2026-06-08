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
    private Iide.AppActionsManager action_manager;
    private SimpleActionGroup simple_action_group = new SimpleActionGroup ();

    public signal void zoom_changed (int zoom_level);

    public Application () {
        Object (
                application_id: "org.github.kai66673.iide",
                flags: ApplicationFlags.DEFAULT_FLAGS,
                resource_base_path: "/org/github/kai66673/iide"
        );
    }

    construct {
        settings = Iide.SettingsService.get_instance ();
        action_manager = Iide.AppActionsManager.get_instance ();

        register_builtin_actions ();
    }

    private void register_builtin_actions () {
        action_manager.register_action (this, new SaveAllAction (this));
        action_manager.register_action (this, new OpenProjectAction (this));
        action_manager.register_action (this, new PreferencesAction (this));
        action_manager.register_action (this, new ToggleMinimapAction (this));
        action_manager.register_action (this, new FuzzyFinderAction (this));
        action_manager.register_action (this, new SearchSymbolAction (this));
        action_manager.register_action (this, new SearchInFilesAction (this));
        action_manager.register_action (this, new ZoomInAction ());
        action_manager.register_action (this, new ZoomOutAction ());
        action_manager.register_action (this, new ZoomResetAction ());
        action_manager.register_action (this, new ExpandSelectionAction ());
        action_manager.register_action (this, new ShrinkSelectionAction ());
        action_manager.register_action (this, new QuitAction ());
        action_manager.register_action (this, new NavigationBackAction (this));
        action_manager.register_action (this, new NavigationForwardAction (this));
        action_manager.register_action (this, new ShowLineNumbersAction (this));
        action_manager.register_action (this, new ShowDiagnosticsMarksAction (this));
        action_manager.register_action (this, new ShowFoldingAction (this));
        action_manager.register_action (this, new FormatAction ());
        action_manager.register_action (this, new ToggleBookmarkAction ());

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

    public Iide.SettingsService get_settings () {
        return settings;
    }

    public void register_embedded_fonts () {
        // Путь к шрифту в GResource
        // string font_path = "/org/github/kai66673/iide/fonts/SymbolsNerdFontMono-Regular.ttf";
        // var bytes = resources_lookup_data (font_path, ResourceLookupFlags.NONE);

        // В GTK4 для кастомных шрифтов из памяти используется PangoCairo и FontConfig
        // На Linux/Arch самый простой способ - создать временный конфиг
        // или использовать Fontconfig напрямую.

        // Но есть способ проще для GTK4 через CSS (начиная с новых версий):
        string css = """
            @font-face {
                font-family: "Symbols Nerd Font";
                src: url("resource:///org/github/kai66673/iide/fonts/SymbolsNerdFont-Regular.ttf");
            }
        """;
        var provider = new Gtk.CssProvider ();
        provider.load_from_bytes (new GLib.Bytes (css.data));
        add_provider_to_display (
                                 Gdk.Display.get_default (),
                                 provider,
                                 Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        );
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

        var css_symbol_provider = new Gtk.CssProvider ();
        css_symbol_provider.load_from_resource ("/org/github/kai66673/iide/symbols/symbols.css");
        add_provider_to_display (
                                 Gdk.Display.get_default (),
                                 css_symbol_provider,
                                 Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        );

        register_embedded_fonts ();

        var win = this.active_window ?? new Iide.Window (this);
        win.present ();
    }
}

private class Iide.SaveAllAction : Iide.AppAction {
    private weak Iide.Application app;

    public SaveAllAction (Iide.Application app) {
        this.app = app;
    }

    public override string id { get { return "save"; } }
    public override string name { get { return _("Save All"); } }
    public override string? description { get { return _("Save all open documents"); } }
    public override string? icon_name { get { return "document-save-symbolic"; } }
    public override string? category { get { return "File"; } }
    public override string? default_shortcut { get { return "<primary>s"; } }

    public override bool can_execute () {
        return app ? .active_window is Iide.Window;
    }

    public override void execute () {
        var win = app ? .active_window as Iide.Window;
        win?.save_modified ();
    }
}

private class Iide.OpenProjectAction : Iide.AppAction {
    private weak Iide.Application app;

    public OpenProjectAction (Iide.Application app) {
        this.app = app;
    }

    public override string id { get { return "open-project"; } }
    public override string name { get { return _("Open Project"); } }
    public override string? description { get { return _("Open a project folder"); } }
    public override string? icon_name { get { return "folder-open-symbolic"; } }
    public override string? category { get { return "File"; } }
    public override string? default_shortcut { get { return "<primary>o"; } }

    public override bool can_execute () {
        return true;
    }

    public override void execute () {
        var win = app ? .active_window as Iide.Window;
        win?.open_project_dialog ();
    }
}

private class Iide.PreferencesAction : Iide.AppAction {
    private weak Iide.Application app;

    public PreferencesAction (Iide.Application app) {
        this.app = app;
    }

    public override string id { get { return "preferences"; } }
    public override string name { get { return _("Preferences"); } }
    public override string? description { get { return _("Open preferences dialog"); } }
    public override string? icon_name { get { return "preferences-system-symbolic"; } }
    public override string? category { get { return "Application"; } }
    public override string? default_shortcut { get { return "<primary>comma"; } }

    public override bool can_execute () {
        return true;
    }

    public override void execute () {
        var dialog = new Iide.PreferencesDialog ();
        dialog.set_transient_for (app ? .active_window);
        dialog.present ();
    }
}

private class Iide.ToggleMinimapAction : Iide.AppAction {
    private weak Iide.Application app;

    public ToggleMinimapAction (Iide.Application app) {
        this.app = app;
        this.state = Iide.SettingsService.get_instance ().show_minimap;
    }

    public override string id { get { return "show-minimap"; } }
    public override string name { get { return _("Toggle Minimap"); } }
    public override string? description { get { return _("Show or hide the minimap"); } }
    public override string? icon_name { get { return "view-fullscreen-symbolic"; } }
    public override string? category { get { return "View"; } }
    public override bool is_toggle { get { return true; } }
    public override string? default_shortcut { get { return "<primary>m"; } }

    public override bool can_execute () {
        return true;
    }

    public override void execute () {
        var settings = Iide.SettingsService.get_instance ();
        state = !state;
        settings.show_minimap = state;

        state_changed (state);
        // TODO: handle changing state from preferences dialog...
    }
}

private class Iide.ZoomInAction : Iide.AppAction {
    private Iide.SettingsService settings;

    public override string id { get { return "zoom-in"; } }
    public override string name { get { return _("Zoom In"); } }
    public override string? description { get { return _("Increase editor font size"); } }
    public override string? icon_name { get { return "zoom-in-symbolic"; } }
    public override string? category { get { return "View"; } }
    public override string? default_shortcut { get { return "<primary>plus"; } }

    public override bool can_execute () {
        settings = Iide.SettingsService.get_instance ();
        return settings.editor_font_size < Iide.FontSizeHelper.MAX_ZOOM_LEVEL;
    }

    public override void execute () {
        settings = Iide.SettingsService.get_instance ();
        var app = GLib.Application.get_default () as Iide.Application;
        settings.editor_font_size++;
        app?.zoom_changed (settings.editor_font_size);
    }
}

private class Iide.ZoomOutAction : Iide.AppAction {
    private Iide.SettingsService settings;

    public override string id { get { return "zoom-out"; } }
    public override string name { get { return _("Zoom Out"); } }
    public override string? description { get { return _("Decrease editor font size"); } }
    public override string? icon_name { get { return "zoom-out-symbolic"; } }
    public override string? category { get { return "View"; } }
    public override string? default_shortcut { get { return "<primary>minus"; } }

    public override bool can_execute () {
        settings = Iide.SettingsService.get_instance ();
        return settings.editor_font_size > Iide.FontSizeHelper.MIN_ZOOM_LEVEL;
    }

    public override void execute () {
        settings = Iide.SettingsService.get_instance ();
        var app = GLib.Application.get_default () as Iide.Application;
        settings.editor_font_size--;
        app?.zoom_changed (settings.editor_font_size);
    }
}

private class Iide.ZoomResetAction : Iide.AppAction {
    private Iide.SettingsService settings;

    public override string id { get { return "zoom-reset"; } }
    public override string name { get { return _("Zoom Reset"); } }
    public override string? description { get { return _("Reset editor font size to default"); } }
    public override string? icon_name { get { return "zoom-original-symbolic"; } }
    public override string? category { get { return "View"; } }
    public override string? default_shortcut { get { return "<primary>0"; } }

    public override bool can_execute () {
        return true;
    }

    public override void execute () {
        settings = Iide.SettingsService.get_instance ();
        var app = GLib.Application.get_default () as Iide.Application;
        settings.editor_font_size = Iide.FontSizeHelper.DEFAULT_ZOOM_LEVEL;
        app?.zoom_changed (settings.editor_font_size);
    }
}

private class Iide.ExpandSelectionAction : Iide.AppAction {
    public override string id { get { return "expand-selection"; } }
    public override string name { get { return _("Expand Selection"); } }
    public override string? description { get { return _("Expand the current selection"); } }
    public override string? icon_name { get { return "zoom-original-symbolic"; } }
    public override string? category { get { return "View"; } }
    public override string? default_shortcut { get { return "<primary>w"; } }

    public override bool can_execute () {
        return true;
    }

    public override void execute () {
        var app = GLib.Application.get_default () as Iide.Application;
        var win = app ? .active_window as Iide.Window;
        if (win != null) {
            win.get_active_source_view () ? .expand_selection ();
        }
    }
}

private class Iide.ShrinkSelectionAction : Iide.AppAction {
    public override string id { get { return "shrink-selection"; } }
    public override string name { get { return _("Shrink Selection"); } }
    public override string? description { get { return _("Shrink the current selection"); } }
    public override string? icon_name { get { return "zoom-original-symbolic"; } }
    public override string? category { get { return "View"; } }
    public override string? default_shortcut { get { return "<primary><shift>w"; } }

    public override bool can_execute () {
        return true;
    }

    public override void execute () {
        var app = GLib.Application.get_default () as Iide.Application;
        var win = app ? .active_window as Iide.Window;
        if (win != null) {
            win.get_active_source_view () ? .shrink_selection ();
        }
    }
}

private class Iide.QuitAction : Iide.AppAction {
    public override string id { get { return "quit"; } }
    public override string name { get { return _("Quit"); } }
    public override string? description { get { return _("Quit the application"); } }
    public override string? icon_name { get { return "application-exit-symbolic"; } }
    public override string? category { get { return "Application"; } }
    public override string? default_shortcut { get { return "<primary>q"; } }

    public override bool can_execute () {
        return true;
    }

    public override void execute () {
        var app = GLib.Application.get_default () as Iide.Application;
        var win = app ? .active_window as Iide.Window;
        if (win != null) {
            win.close ();
        } else {
            app?.quit ();
        }
    }
}

private class Iide.FuzzyFinderAction : Iide.AppAction {
    private weak Iide.Application app;

    public FuzzyFinderAction (Iide.Application app) {
        this.app = app;
    }

    public override string id { get { return "fuzzy-finder"; } }
    public override string name { get { return _("Quick Open"); } }
    public override string? description { get { return _("Open a file quickly by name"); } }
    public override string? icon_name { get { return "system-search-symbolic"; } }
    public override string? category { get { return "File"; } }
    public override string? default_shortcut { get { return "<primary>p"; } }

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

private class Iide.SearchSymbolAction : Iide.AppAction {
    private weak Iide.Application app;

    public SearchSymbolAction (Iide.Application app) {
        this.app = app;
    }

    public override string id { get { return "search-symbol"; } }
    public override string name { get { return _("Search  Symbol"); } }
    public override string? description { get { return _("Search Symbol in Project"); } }
    public override string? icon_name { get { return "system-search-symbolic"; } }
    public override string? category { get { return "Edit"; } }
    public override string? default_shortcut { get { return "<primary>t"; } }

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

private class Iide.SearchInFilesAction : Iide.AppAction {
    private weak Iide.Application app;

    public SearchInFilesAction (Iide.Application app) {
        this.app = app;
    }

    public override string id { get { return "search-in-files"; } }
    public override string name { get { return _("Search in Files"); } }
    public override string? description { get { return _("Search for text in all project files"); } }
    public override string? icon_name { get { return "edit-find-symbolic"; } }
    public override string? category { get { return "Edit"; } }
    public override string? default_shortcut { get { return "<primary><shift>f"; } }

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

private class Iide.NavigationBackAction : Iide.AppAction {
    private weak Iide.Application app;

    public NavigationBackAction (Iide.Application app) {
        this.app = app;
    }

    public override string id { get { return "navigation-back"; } }
    public override string name { get { return _("Navigation Back"); } }
    public override string? description { get { return _("Navigation Back"); } }
    public override string? icon_name { get { return "go-previous-symbolic"; } }
    public override string? category { get { return "Application"; } }
    public override string? default_shortcut { get { return "<Alt>Left"; } }

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

private class Iide.NavigationForwardAction : Iide.AppAction {
    private weak Iide.Application app;

    public NavigationForwardAction (Iide.Application app) {
        this.app = app;
    }

    public override string id { get { return "navigation-forward"; } }
    public override string name { get { return _("Navigation Forward"); } }
    public override string? description { get { return _("Navigation Forward"); } }
    public override string? icon_name { get { return "go-next-symbolic"; } }
    public override string? category { get { return "Application"; } }
    public override string? default_shortcut { get { return "<Alt>Right"; } }

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

private class Iide.ShowLineNumbersAction : Iide.AppAction {
    private weak Iide.Application app;

    public ShowLineNumbersAction (Iide.Application app) {
        this.app = app;
        this.state = Iide.SettingsService.get_instance ().show_minimap;
    }

    public override string id { get { return "show-line-numbers"; } }
    public override string name { get { return _("Show Line Numbers"); } }
    public override string? description { get { return _("Show or hide line numbers gutter"); } }
    public override string? icon_name { get { return "view-fullscreen-symbolic"; } }
    public override string? category { get { return "View"; } }
    public override bool is_toggle { get { return true; } }
    public override string? default_shortcut { get { return "<primary><Alt>n"; } }

    public override bool can_execute () {
        return true;
    }

    public override void execute () {
        var settings = Iide.SettingsService.get_instance ();
        state = !state;
        settings.show_line_numbers = state;

        state_changed (state);
        // TODO: handle changing state from preferences dialog...
    }
}

private class Iide.ShowDiagnosticsMarksAction : Iide.AppAction {
    private weak Iide.Application app;

    public ShowDiagnosticsMarksAction (Iide.Application app) {
        this.app = app;
        this.state = Iide.SettingsService.get_instance ().show_minimap;
    }

    public override string id { get { return "show-diagnostics-marks"; } }
    public override string name { get { return _("Show Diagnostics"); } }
    public override string? description { get { return _("Show or hide diagnostics marks gutter"); } }
    public override string? icon_name { get { return "view-fullscreen-symbolic"; } }
    public override string? category { get { return "View"; } }
    public override bool is_toggle { get { return true; } }
    public override string? default_shortcut { get { return "<primary><Alt>m"; } }

    public override bool can_execute () {
        return true;
    }

    public override void execute () {
        var settings = Iide.SettingsService.get_instance ();
        state = !state;
        settings.show_diagnostics_marks = state;

        state_changed (state);
        // TODO: handle changing state from preferences dialog...
    }
}

private class Iide.ShowFoldingAction : Iide.AppAction {
    private weak Iide.Application app;

    public ShowFoldingAction (Iide.Application app) {
        this.app = app;
        this.state = Iide.SettingsService.get_instance ().show_minimap;
    }

    public override string id { get { return "show-folding-gutter"; } }
    public override string name { get { return _("Show Folding Gutter"); } }
    public override string? description { get { return _("Show or hide folding gutter"); } }
    public override string? icon_name { get { return "view-fullscreen-symbolic"; } }
    public override string? category { get { return "View"; } }
    public override bool is_toggle { get { return true; } }
    public override string? default_shortcut { get { return "<primary><Alt>f"; } }

    public override bool can_execute () {
        return true;
    }

    public override void execute () {
        var settings = Iide.SettingsService.get_instance ();
        state = !state;
        settings.show_folding_gutter = state;

        state_changed (state);
        // TODO: handle changing state from preferences dialog...
    }
}

private class Iide.FormatAction : Iide.AppAction {
    public override string id { get { return "format"; } }
    public override string name { get { return _("Format"); } }
    public override string? description { get { return _("Format entire current document"); } }
    public override string? icon_name { get { return "zoom-original-symbolic"; } }
    public override string? category { get { return "View"; } }
    public override string? default_shortcut { get { return "<primary><shift>i"; } }

    public override bool can_execute () {
        return true;
    }

    public override void execute () {
        var app = GLib.Application.get_default () as Iide.Application;
        var win = app ? .active_window as Iide.Window;
        if (win != null) {
            var source_view = win.get_active_source_view ();
            if (source_view != null){
                source_view.format_document.begin ();
            }
        }
    }
}

private class Iide.ToggleBookmarkAction : Iide.AppAction {
    public override string id { get { return "toggle-bookmark"; } }
    public override string name { get { return _("Toggle bookmark"); } }
    public override string? description { get { return _("Toggle bookmark at current line"); } }
    public override string? icon_name { get { return "zoom-original-symbolic"; } }
    public override string? category { get { return "View"; } }
    public override string? default_shortcut { get { return "<primary>F2"; } }

    public override bool can_execute () {
        return true;
    }

    public override void execute () {
        var app = GLib.Application.get_default () as Iide.Application;
        var win = app ? .active_window as Iide.Window;
        if (win != null) {
            var source_view = win.get_active_source_view ();
            if (source_view != null){
                source_view.toggle_bookmark_on_current_line ();
            }
        }
    }
}

