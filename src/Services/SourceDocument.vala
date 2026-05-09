/*
*/

class Iide.SourceDocument: GLib.Object {
    public signal void document_changed(PendingChange new_change);

    public SourceDocument(SourceView source_view) {
        Object();

        source_view.buffer.insert_text.connect ((ref location, text, len) => {
            var change = new PendingChange (text, location);
            this.document_changed (change);
        });

        source_view.buffer.delete_range.connect ((start, end) => {
            var change = new PendingChange ("", start, end);
            this.document_changed (change);
        });
    }
}