/*
*/

public struct Iide.BookMarkInfo {
    public int line_number; // 0-based
    public string line_text;
}

public class Iide.SourceBookMark : GtkSource.Mark {
    public string description { get; construct set; }
    
    public SourceBookMark(string description = "") {
        Object(
            name: null,
            category: "bookmark",
            description: description
        );
    }
}
