namespace Iide {
    public string mime_type_for_file(GLib.File file) {
        string mime_type = "text-x";
        try {
            var info = file.query_info("standard::*", FileQueryInfoFlags.NONE, null);
            mime_type = ContentType.get_mime_type(info.get_attribute_as_string(FileAttribute.STANDARD_CONTENT_TYPE));
        } catch (Error e) {
        }
        return mime_type;
    }
}
