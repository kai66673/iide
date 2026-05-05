/*
 */

public class Iide.PythonTreeSitterIndenter : BaseTreeSitterIndenter {
    private const string PYTHON_INDENT_QUERY = """
        ; Узлы, которые открывают новый уровень отступа (class_definition) @indent.begin
        (function_definition) @indent.begin
        (if_statement) @indent.begin
        (elif_clause) @indent.begin
        (else_clause) @indent.begin
        (for_statement) @indent.begin
        (while_statement) @indent.begin
        (with_statement) @indent.begin
        (try_statement) @indent.begin
        (except_clause) @indent.begin
        (finally_clause) @indent.begin
        (parenthesized_expression) @indent.begin
        (list) @indent.begin
        (dictionary) @indent.begin
        (argument_list) @indent.begin
        (parameters) @indent.begin
    """;

    public PythonTreeSitterIndenter (TreeSitter.Language lang) {
        base (lang);
    }

    public override string get_indent_query_string () {
        return PYTHON_INDENT_QUERY;
    }
}