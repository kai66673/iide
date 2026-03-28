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

using Adw;

public class Iide.PanelLayoutHelper : Object {

    public class WidgetInfo {
        public string title { get; set; }
        public string icon_name { get; set; }
        public string id { get; set; }
        public string kind { get; set; }
        public int area { get; set; }
        public uint column { get; set; }
        public uint row { get; set; }
        public uint depth { get; set; }
    }

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

        builder.set_member_name ("widgets");
        builder.begin_array ();

        dock.foreach_frame ((frame) => {
            var pages = frame.get_pages ();
            var position = frame.get_position ();

            for (uint i = 0; i < pages.get_n_items (); i++) {
                var item = pages.get_item (i) as Adw.TabPage;
                if (item == null) {
                    continue;
                }
                var child = item.get_child ();
                if (child == null) {
                    continue;
                }
                var widget = child as Panel.Widget;
                if (widget == null) {
                    continue;
                }

                builder.begin_object ();
                builder.set_member_name ("title");
                builder.add_string_value (widget.get_title () ?? "");
                builder.set_member_name ("icon_name");
                builder.add_string_value (widget.get_icon_name () ?? "");
                builder.set_member_name ("id");
                builder.add_string_value (widget.get_id () ?? "");
                builder.set_member_name ("kind");
                builder.add_string_value (widget.get_kind () ?? "");

                if (position != null) {
                    builder.set_member_name ("area");
                    builder.add_int_value ((int) position.get_area ());
                    builder.set_member_name ("column");
                    builder.add_int_value ((int) position.get_column ());
                    builder.set_member_name ("row");
                    builder.add_int_value ((int) position.get_row ());
                    builder.set_member_name ("depth");
                    builder.add_int_value ((int) position.get_depth ());
                }

                builder.end_object ();
            }
        });

        builder.end_array ();
        builder.end_object ();

        var generator = new Json.Generator ();
        generator.root = builder.get_root ();
        return generator.to_data (null);
    }

    public static Gee.ArrayList<WidgetInfo> parse_widgets (string data) {
        var result = new Gee.ArrayList<WidgetInfo> ();

        if (data == null || data == "") {
            return result;
        }

        try {
            var parser = new Json.Parser ();
            parser.load_from_data (data);
            var root = parser.get_root ().get_object ();

            if (root.has_member ("widgets")) {
                var widgets_array = root.get_array_member ("widgets");
                foreach (var node in widgets_array.get_elements ()) {
                    var obj = node.get_object ();
                    var info = new WidgetInfo ();
                    info.title = obj.get_string_member ("title");
                    info.icon_name = obj.has_member ("icon_name") ? obj.get_string_member ("icon_name") : "";
                    info.id = obj.has_member ("id") ? obj.get_string_member ("id") : "";
                    info.kind = obj.has_member ("kind") ? obj.get_string_member ("kind") : "";
                    info.area = obj.has_member ("area") ? (int) obj.get_int_member ("area") : -1;
                    info.column = obj.has_member ("column") ? (uint) obj.get_int_member ("column") : 0;
                    info.row = obj.has_member ("row") ? (uint) obj.get_int_member ("row") : 0;
                    info.depth = obj.has_member ("depth") ? (uint) obj.get_int_member ("depth") : 0;
                    result.add (info);
                }
            }
        } catch (Error e) {
            warning ("Failed to parse widgets: %s", e.message);
        }

        return result;
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
