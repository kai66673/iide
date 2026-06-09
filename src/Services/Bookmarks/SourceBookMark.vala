/*
*/

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
