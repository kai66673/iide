public class Iide.MatchRange : Object {
    public int start { get; construct; }
    public int end { get; construct; }

    public MatchRange (int start, int end) {
        Object (start: start, end: end);
    }
}


public class Iide.SearchResult : Object {
    public string file_path { get; construct; }
    public string relative_path { get; construct; }
    public int line_number { get; construct; }
    public string line_content { get; construct; }
    public Gee.List<MatchRange>? matches { get; construct; }
    public string? icon_name { get; construct; }
    public int score { get; construct; }

    public SearchResult (string file_path,
        string relative_path,
        int line_number,
        string line_content,
        Gee.List<MatchRange>? matches = null,
        string? icon_name = null,
        int score = 0) {
        Object (
                file_path : file_path,
                relative_path : relative_path,
                line_number: line_number,
                line_content: line_content,
                matches: matches,
                icon_name: icon_name,
                score: score
        );
    }
}
