// Whole-file syntax entry point. Individual declaration and statement
// parsers retain their prefix APIs for embedding.
pub import "declaration_parser.rl"

pub struct ProgramParseResult {
    pub let program: NodeId?;
    // Every syntax error in the file, in source order; the program is nil when any exist.
    pub let errors: Vec<SyntaxError>;
}

def declaration_starts(tokens: Vec<LexToken>, index: i32) -> Bool {
    let word = tokens[index].text;
    switch word {
        case "import", "typealias", "struct", "enum", "protocol",
             "extension", "def", "extern", "pub", "private", "internal", "let", "var":
            return true;
        case "unsafe":
            if index + 1 < tokens.len() {
                let next = tokens[index + 1].text;
                return next.equals("def") || next.equals("static");
            }
        case "static", "parallel":
            if index + 1 < tokens.len() { return tokens[index + 1].text.equals("def"); }
        default: {}
    }
    false
}

pub def parse_program_tokens(tokens: Vec<LexToken>, arena: AstArena) -> ProgramParseResult {
    let items = Vec<NodeId>.new();
    let errors = Vec<SyntaxError>.new();
    var index = 0;
    while index < tokens.len() - 1 {
        let token = tokens[index];
        if !declaration_starts(tokens, index) {
            errors.push(SyntaxError {
                message: f"expected a declaration, found '{token.text}' (statements belong inside functions; module-level constants use `let`)",
                span: token.span });
            index = next_declaration(tokens, index, token.span);
            continue;
        }
        let result = parse_declaration_prefix(tokens, arena, index);
        var problem = result.error;
        var incomplete = result.remaining.len() > 0 || result.next_index <= index;
        if let failed = problem { incomplete = false; }
        if incomplete { problem = SyntaxError { message: "incomplete declaration", span: tokens[result.next_index].span }; }
        for recovered in arena.syntax_errors { errors.push(recovered); }
        while arena.syntax_errors.len() > 0 { arena.syntax_errors.pop(); }
        if let failure = problem {
            errors.push(failure);
            if !arena.recovering { break; }
            index = next_declaration(tokens, index, failure.span);
            continue;
        }
        if let item = result.declaration { items.push(item); }
        for extra in result.extra { items.push(extra); }
        index = result.next_index;
    }
    if errors.len() > 0 { return ProgramParseResult { program: nil, errors: sorted_errors(errors) }; }
    var span = Span.new(1, 1, 1, 1);
    if items.len() > 0 {
        let start = tokens[0].span;
        let end = tokens[index - 1].span;
        span = Span.new(start.line, start.column, end.end_line, end.end_column);
    }
    ProgramParseResult {
        program: arena.add(NodeForm.program(ProgramAst { items }), span), errors
    }
}

// The next declaration after a failure at `failure`: a declaration keyword
// beginning a later line, indented no deeper than the failed one.
def next_declaration(tokens: Vec<LexToken>, first: i32, failure: Span) -> i32 {
    let column = tokens[first].span.column;
    var index = first + 1;
    while index < tokens.len() - 1 {
        let token = tokens[index];
        if !span_before(token.span, failure) && token.span.line > tokens[index - 1].span.end_line &&
           token.span.column <= column && declaration_starts(tokens, index) { break; }
        index += 1;
    }
    index
}

// Nested bodies record their errors before the enclosing declaration fails.
def sorted_errors(errors: Vec<SyntaxError>) -> Vec<SyntaxError> {
    for index in 1..<errors.len() {
        var position = index;
        while position > 0 && span_before(errors[position].span, errors[position - 1].span) {
            let moved = errors[position];
            errors[position] = errors[position - 1];
            errors[position - 1] = moved;
            position -= 1;
        }
    }
    errors
}

pub def parse_program_text(source: String, arena: AstArena) -> ProgramParseResult {
    let lexed = tokenize(source);
    if let problem = lexed.error {
        return ProgramParseResult { program: nil, errors: [SyntaxError { message: problem.message, span: problem.span }] };
    }
    parse_program_tokens(lexed.tokens, arena)
}
