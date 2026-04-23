namespace Iide {

    public class MatchRange : Object {
        public int start { get; set; }
        public int end { get; set; }

        public MatchRange (int start, int end) {
            Object (start: start, end: end);
        }
    }


    public class SearchResult : Object {
        public string file_path { get; set; }
        public string relative_path { get; set; }
        public int line_number { get; set; }
        public string line_content { get; set; }
        public Gee.List<MatchRange>? matches { get; set; }
        public string? icon_name { get; set; }
        public int score { get; set; }

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
}
