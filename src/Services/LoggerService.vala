/*
 * loggerservice.vala
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

using GLib;

public enum Iide.LogLevel {
    DEBUG,
    INFO,
    WARNING,
    ERROR,
    CRITICAL;

    public string to_string () {
        switch (this) {
        case DEBUG:    return "DEBUG";
        case INFO:     return "INFO";
        case WARNING:  return "WARN";
        case ERROR:    return "ERROR";
        case CRITICAL: return "CRITICAL";
        default:       return "UNKNOWN";
        }
    }

    public string get_color () {
        switch (this) {
        case DEBUG:    return "#888888";
        case INFO:     return "#4a9eff";
        case WARNING:  return "#f5a623";
        case ERROR:    return "#e74c3c";
        case CRITICAL: return "#ff4757";
        default:       return "#ffffff";
        }
    }
}

public class Iide.LogEntry : Object {
    public int64 timestamp { get; set; }
    public Iide.LogLevel level { get; set; }
    public string domain { get; set; }
    public string message { get; set; }
    public string? details { get; set; }

    public string get_timestamp_string () {
        var time = new DateTime.from_unix_utc (timestamp / 1000000);
        var local = time.to_timezone (new TimeZone.local ());
        var msec = (int) ((timestamp / 1000) % 1000);
        return "%s.%03d".printf (local.format ("%H:%M:%S"), msec);
    }
}

public class Iide.LoggerService : Object {
    private static LoggerService? _instance;
    private Gee.ArrayList<Iide.LogEntry> entries;
    private int max_entries = 1000;
    private bool enable_logging = true;
    private File log_file;

    public signal void log_added (Iide.LogEntry entry);
    public signal void log_cleared ();

    public static LoggerService get_instance () {
        if (_instance == null) {
            _instance = new LoggerService ();
        }
        return _instance;
    }

    private LoggerService () {
        entries = new Gee.ArrayList<Iide.LogEntry> ();
        log_file = File.new_for_path (
                                      Path.build_filename (Environment.get_user_data_dir (), "iide", "iide.log")
        );
        try {
            var dir = log_file.get_parent ();
            if (dir != null && !dir.query_exists (null)) {
                dir.make_directory_with_parents (null);
            }
        } catch (Error e) {
            stderr.printf ("Failed to create log directory: %s\n", e.message);
        }
    }

    public void log (LogLevel level, string domain, string message, string? details = null) {
        if (!enable_logging)return;

        var entry = new Iide.LogEntry () {
            timestamp = (int64) get_real_time (),
            level = level,
            domain = domain,
            message = message,
            details = details
        };

        entries.add (entry);

        if (entries.size > max_entries) {
            entries.remove_at (0);
        }

        log_to_file (entry);
        log_added (entry);
    }

    public void debug (string domain, string message, string? details = null) {
        log (LogLevel.DEBUG, domain, message, details);
    }

    public void info (string domain, string message, string? details = null) {
        log (LogLevel.INFO, domain, message, details);
    }

    public void warning (string domain, string message, string? details = null) {
        log (LogLevel.WARNING, domain, message, details);
    }

    public void error (string domain, string message, string? details = null) {
        log (LogLevel.ERROR, domain, message, details);
    }

    public void critical (string domain, string message, string? details = null) {
        log (LogLevel.CRITICAL, domain, message, details);
    }

    private void log_to_file (LogEntry entry) {
        try {
            var time = new DateTime.from_unix_utc (entry.timestamp / 1000000);
            var local = time.to_timezone (new TimeZone.local ());
            var timestamp = local.format ("%Y-%m-%d %H:%M:%S");
            var details_str = entry.details != null ? " | " + entry.details : "";
            var line = "[%s] [%s] [%s] %s%s\n".printf (timestamp, entry.level.to_string (), entry.domain, entry.message, details_str);

            if (log_file.query_exists (null)) {
                log_file.append_to (FileCreateFlags.NONE, null).write (line.data);
            } else {
                log_file.create (FileCreateFlags.REPLACE_DESTINATION, null).write (line.data);
            }
        } catch (Error e) {
            stderr.printf ("Failed to write to log file: %s\n", e.message);
        }
    }

    public Gee.ArrayList<Iide.LogEntry> get_entries () {
        return entries;
    }

    public Gee.ArrayList<Iide.LogEntry> get_entries_by_level (LogLevel level) {
        var result = new Gee.ArrayList<Iide.LogEntry> ();
        foreach (var entry in entries) {
            if (entry.level == level) {
                result.add (entry);
            }
        }
        return result;
    }

    public void clear () {
        entries.clear ();
        log_cleared ();
    }

    public void set_max_entries (int max) {
        max_entries = max;
        while (entries.size > max_entries) {
            entries.remove_at (0);
        }
    }

    public void set_logging_enabled (bool enabled) {
        enable_logging = enabled;
    }
}
