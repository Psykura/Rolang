// Whole-file syntax entry point. Individual declaration and statement
// parsers retain their prefix APIs for embedding.
pub import "declaration_parser.rl"

pub struct ProgramParseResult {
    pub let program: NodeId?;
    pub let error: String?;
}

def declaration_starts(tokens: Vec<LexToken>, index: i32) -> Bool {
    let word = tokens[index].text;
    switch word {
        case "import", "typealias", "struct", "enum", "protocol",
             "extension", "def", "extern", "pub", "private", "internal":
            return true;
        case "unsafe":
            if index + 1 < tokens.len() {
                let next = tokens[index + 1].text;
                return next.equals("def") || next.equals("static");
            }
        case "static":
            if index + 1 < tokens.len() { return tokens[index + 1].text.equals("def"); }
        default: {}
    }
    false
}

pub def parse_program_tokens(tokens: Vec<LexToken>, arena: AstArena) -> ProgramParseResult {
    let items = Vec<NodeId>.new();
    var index = 0;
    while index < tokens.len() - 1 {
        if declaration_starts(tokens, index) {
            let result = parse_declaration_prefix(tokens, arena, index);
            if let problem = result.error {
                return ProgramParseResult { program: nil, error: problem };
            }
            if result.remaining.len() > 0 || result.next_index <= index {
                return ProgramParseResult { program: nil, error: "incomplete declaration" };
            }
            guard let item = result.declaration else {
                return ProgramParseResult { program: nil, error: "missing declaration" };
            }
            items.push(item);
            for extra in result.extra { items.push(extra); }
            index = result.next_index;
        } else {
            let result = parse_statement_prefix(tokens, arena, index);
            if let problem = result.error {
                return ProgramParseResult { program: nil, error: problem };
            }
            if result.next_index <= index {
                return ProgramParseResult { program: nil, error: "incomplete statement" };
            }
            guard let item = result.statement else {
                return ProgramParseResult { program: nil, error: "missing statement" };
            }
            items.push(item);
            index = result.next_index;
        }
    }
    var span = Span.new(1, 1, 1, 1);
    if items.len() > 0 {
        let start = tokens[0].span;
        let end = tokens[index - 1].span;
        span = Span.new(start.line, start.column, end.end_line, end.end_column);
    }
    ProgramParseResult {
        program: arena.add(NodeForm.program(ProgramAst { items }), span), error: nil
    }
}

pub def parse_program_text(source: String, arena: AstArena) -> ProgramParseResult {
    let lexed = tokenize(source);
    if let problem = lexed.error {
        return ProgramParseResult { program: nil, error: problem.message };
    }
    parse_program_tokens(lexed.tokens, arena)
}
