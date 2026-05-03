/*
 */

public class Iide.PythonTreeSitterIndenter : BaseTreeSitterIndenter {
    private const string PYTHON_INDENT_QUERY = """
        (class_definition)@indent
        (function_definition) @indent
        (if_statement) @indent
        (elif_clause) @indent
        (else_clause) @indent
        (for_statement) @indent
        (while_statement) @indent
        (with_statement) @indent
        (try_statement) @indent
        (except_clause) @indent
        (finally_clause) @indent
        (list) @indent
        (dictionary) @indent
        (parenthesized_expression) @indent
    """;

    public PythonTreeSitterIndenter (TreeSitter.Language lang) {
        base (lang);
    }

    public override string get_indent_query_string () {
        return PYTHON_INDENT_QUERY;
    }
}