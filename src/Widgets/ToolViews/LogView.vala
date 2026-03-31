/*
 * logview.vala
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

public class Iide.LogView : Gtk.Box {
    private Gtk.TextView text_view;
    private Gtk.TextBuffer buffer;
    private Gtk.ScrolledWindow scrolled_window;
    private Gtk.Button clear_button;
    private Gtk.ToggleButton wrap_button;
    private Gtk.DropDown level_filter;
    private Gtk.SearchEntry search_entry;
    private Iide.LoggerService logger;

    private bool auto_scroll = true;
    private const int MAX_VISIBLE_LINES = 5000;
    private int line_count = 0;

    public LogView () {
        Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);
    }

    construct {
        logger = Iide.LoggerService.get_instance ();

        var toolbar = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
        toolbar.add_css_class ("toolbar");
        toolbar.margin_start = 6;
        toolbar.margin_end = 6;
        toolbar.margin_top = 4;
        toolbar.margin_bottom = 4;

        clear_button = new Gtk.Button () {
            icon_name = "edit-clear-symbolic",
            tooltip_text = _("Clear logs")
        };
        clear_button.clicked.connect (on_clear_clicked);

        wrap_button = new Gtk.ToggleButton () {
            icon_name = "preferences-desktop-text-wrap-symbolic",
            tooltip_text = _("Word wrap")
        };
        wrap_button.active = true;
        wrap_button.toggled.connect (on_wrap_toggled);

        var level_label = new Gtk.Label (_("Level:")) {
            margin_start = 12
        };

        var level_list = new Gtk.StringList ({
            _("All"),
            "DEBUG",
            "INFO",
            "WARN",
            "ERROR",
            "CRITICAL"
        });
        level_filter = new Gtk.DropDown (level_list, null);
        level_filter.selected = 0;
        level_filter.notify["selected"].connect (on_level_changed);

        search_entry = new Gtk.SearchEntry () {
            placeholder_text = _("Search logs..."),
            hexpand = true
        };
        search_entry.search_changed.connect (on_search_changed);

        toolbar.append (clear_button);
        toolbar.append (wrap_button);
        toolbar.append (new Gtk.Separator (Gtk.Orientation.VERTICAL));
        toolbar.append (level_label);
        toolbar.append (level_filter);
        toolbar.append (search_entry);

        buffer = new Gtk.TextBuffer (null);
        buffer.create_tag ("debug", foreground: "#888888");
        buffer.create_tag ("info", foreground: "#4a9eff");
        buffer.create_tag ("warning", foreground: "#f5a623");
        buffer.create_tag ("error", foreground: "#e74c3c");
        buffer.create_tag ("critical", foreground: "#ff4757", weight: Pango.Weight.BOLD);
        buffer.create_tag ("bold", weight: Pango.Weight.BOLD);
        buffer.create_tag ("dim", foreground: "#666666");

        text_view = new Gtk.TextView () {
            buffer = buffer,
            editable = false,
            monospace = true,
            wrap_mode = Gtk.WrapMode.WORD_CHAR,
            hscroll_policy = Gtk.ScrollablePolicy.NATURAL,
            vscroll_policy = Gtk.ScrollablePolicy.NATURAL
        };
        text_view.add_css_class ("log-view");

        scrolled_window = new Gtk.ScrolledWindow () {
            child = text_view,
            hexpand = true,
            vexpand = true
        };

        append (toolbar);
        append (scrolled_window);

        logger.log_added.connect (on_log_added);
        logger.log_cleared.connect (on_log_cleared);

        foreach (var entry in logger.get_entries ()) {
            append_entry (entry);
        }
    }

    private void on_log_added (Iide.LogEntry entry) {
        append_entry (entry);
    }

    private void append_entry (Iide.LogEntry entry) {
        Gtk.TextIter end;
        buffer.get_end_iter (out end);

        var timestamp = entry.get_timestamp_string ();
        var level_str = entry.level.to_string ();
        var domain = entry.domain;
        var message = entry.message;

        string tag_name;
        switch (entry.level) {
            case Iide.LogLevel.DEBUG:
                tag_name = "debug";
                break;
            case Iide.LogLevel.INFO:
                tag_name = "info";
                break;
            case Iide.LogLevel.WARNING:
                tag_name = "warning";
                break;
            case Iide.LogLevel.ERROR:
                tag_name = "error";
                break;
            case Iide.LogLevel.CRITICAL:
                tag_name = "critical";
                break;
            default:
                tag_name = "dim";
                break;
        }

        var ts_text = "[%s] ".printf (timestamp);
        var level_text = "[%s] ".printf (level_str);
        var domain_text = "[%s] ".printf (domain);

        var start = end;
        buffer.insert (ref end, ts_text, ts_text.length);
        buffer.apply_tag_by_name ("dim", start, end);

        start = end;
        buffer.insert (ref end, level_text, level_text.length);
        buffer.apply_tag_by_name (tag_name, start, end);

        start = end;
        buffer.insert (ref end, domain_text, domain_text.length);
        buffer.apply_tag_by_name ("bold", start, end);

        start = end;
        buffer.insert (ref end, message, message.length);

        if (entry.details != null) {
            start = end;
            buffer.insert (ref end, "\n  ", 3);
            buffer.apply_tag_by_name ("dim", start, end);

            start = end;
            buffer.insert (ref end, entry.details, entry.details.length);
        }

        start = end;
        buffer.insert (ref end, "\n", 1);

        line_count++;
        if (auto_scroll) {
            scroll_to_end ();
        }

        trim_buffer ();
    }

    private void scroll_to_end () {
        Gtk.TextIter end;
        buffer.get_end_iter (out end);
        text_view.scroll_to_iter (end, 0.0, true, 0.0, 1.0);
    }

    private void trim_buffer () {
        if (line_count > MAX_VISIBLE_LINES) {
            Gtk.TextIter start;
            buffer.get_iter_at_line (out start, line_count - MAX_VISIBLE_LINES);
            Gtk.TextIter end = start;
            buffer.get_iter_at_line (out end, line_count - MAX_VISIBLE_LINES + 100);
            buffer.delete (ref start, ref end);
            line_count -= 100;
        }
    }

    private void on_clear_clicked () {
        logger.clear ();
    }

    private void on_log_cleared () {
        buffer.set_text ("");
        line_count = 0;
    }

    private void on_wrap_toggled () {
        text_view.wrap_mode = wrap_button.active ? Gtk.WrapMode.WORD_CHAR : Gtk.WrapMode.NONE;
    }

    private void on_level_changed () {
        rebuild_log_view ();
    }

    private void on_search_changed () {
        rebuild_log_view ();
    }

    private bool matches_search (Iide.LogEntry entry, string search_text) {
        if (search_text == "") {
            return true;
        }
        var lower_search = search_text.down ();
        return entry.message.down ().contains (lower_search) ||
               entry.domain.down ().contains (lower_search) ||
               (entry.details != null && entry.details.down ().contains (lower_search));
    }

    private void rebuild_log_view () {
        buffer.set_text ("");
        line_count = 0;

        var filter_level = (int) level_filter.selected;
        var search_text = search_entry.text;

        foreach (var entry in logger.get_entries ()) {
            if (filter_level > 0) {
                var entry_level = (int) entry.level + 1;
                if (entry_level != filter_level) {
                    continue;
                }
            }
            if (!matches_search (entry, search_text)) {
                continue;
            }
            append_entry (entry);
        }
    }
}
