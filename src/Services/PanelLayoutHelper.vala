/*
 * panellayouthelper.vala
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

public class Iide.PanelLayoutHelper : Object {

    public static string serialize_dock (Panel.Dock dock) {
        var builder = new Json.Builder ();
        builder.begin_object ();
        builder.set_member_name ("reveal_start");
        builder.add_boolean_value (dock.reveal_start);
        builder.set_member_name ("reveal_end");
        builder.add_boolean_value (dock.reveal_end);
        builder.set_member_name ("reveal_bottom");
        builder.add_boolean_value (dock.reveal_bottom);
        builder.set_member_name ("start_width");
        builder.add_int_value (dock.start_width);
        builder.set_member_name ("end_width");
        builder.add_int_value (dock.end_width);
        builder.set_member_name ("bottom_height");
        builder.add_int_value (dock.bottom_height);
        builder.end_object ();

        var generator = new Json.Generator ();
        generator.root = builder.get_root ();
        return generator.to_data (null);
    }

    public static void deserialize_dock (string data, Panel.Dock dock) {
        if (data == null || data == "") {
            return;
        }

        try {
            var parser = new Json.Parser ();
            parser.load_from_data (data);
            var root = parser.get_root ().get_object ();

            if (root.has_member ("reveal_start")) {
                dock.reveal_start = root.get_boolean_member ("reveal_start");
            }
            if (root.has_member ("reveal_end")) {
                dock.reveal_end = root.get_boolean_member ("reveal_end");
            }
            if (root.has_member ("reveal_bottom")) {
                dock.reveal_bottom = root.get_boolean_member ("reveal_bottom");
            }
            if (root.has_member ("start_width")) {
                dock.start_width = (int) root.get_int_member ("start_width");
            }
            if (root.has_member ("end_width")) {
                dock.end_width = (int) root.get_int_member ("end_width");
            }
            if (root.has_member ("bottom_height")) {
                dock.bottom_height = (int) root.get_int_member ("bottom_height");
            }
        } catch (Error e) {
            warning ("Failed to parse dock layout: %s", e.message);
        }
    }
}
