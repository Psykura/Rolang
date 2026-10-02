// Source locations. AST nodes carry stable NodeIds.
pub struct Span {
    pub var line: i32;
    pub var column: i32;
    pub var end_line: i32 = 0;
    pub var end_column: i32 = 0;
    pub static def new(line: i32, column: i32, end_line: i32 = 0, end_column: i32 = 0) -> Span {
        Span { line, column, end_line, end_column }
    }
}

// A syntax error located at the offending token.
pub struct SyntaxError {
    pub let message: String;
    pub let span: Span;
    pub static def expected(what: String, found: String, span: Span) -> SyntaxError {
        var shown = f"'{found}'";
        if found.len() == 0 { shown = "end of file"; }
        SyntaxError { message: f"expected {what}, found {shown}", span }
    }
}
