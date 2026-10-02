// Recursive-descent parser for patterns.
pub import "literal_parser.rl"

pub struct PatternParseResult {
    pub let pattern: NodeId?;
    pub let next_index: i32;
    pub let error: String?;
}

struct PatternCursor {
    let tokens: Vec<LexToken>;
    let arena: AstArena;
    var index: i32;
    var end_line: i32;
    var end_column: i32;
    var error: String?;

    def current() -> LexToken {
        if self.index < self.tokens.len() { return self.tokens[self.index]; }
        self.tokens[self.tokens.len() - 1]
    }
    def at_identifier() -> Bool {
        switch self.current().kind { case .identifier: true; default: false; }
    }
    def next_identifier() -> Bool {
        if self.index + 1 >= self.tokens.len() { return false; }
        switch self.tokens[self.index + 1].kind { case .identifier: true; default: false; }
    }
    def take() -> String {
        let token = self.current();
        self.end_line = token.span.end_line;
        self.end_column = token.span.end_column;
        self.index += 1;
        token.text
    }
    def match_text(wanted: String) -> Bool {
        if !self.current().text.equals(wanted) { return false; }
        self.take();
        true
    }
    def fail(expected: String) -> Void {
        if let previous = self.error { return; }
        let token = self.current();
        self.error = f"expected {expected} at {token.span.line}:{token.span.column}, found '{token.text}'";
    }
    def expect(wanted: String) -> Bool {
        if self.match_text(wanted) { return true; }
        self.fail(f"'{wanted}'");
        false
    }
    def make(form: NodeForm, start: Span) -> NodeId {
        self.arena.add(form, Span.new(start.line, start.column, self.end_line, self.end_column))
    }
    def parse_pattern() -> NodeId? {
        let start = self.current().span;
        guard let first = self.parse_primary() else { return nil; }
        if !self.match_text("|") { return first; }
        let patterns = Vec<NodeId>.new();
        patterns.push(first);
        while true {
            guard let next = self.parse_primary() else { return nil; }
            patterns.push(next);
            if !self.match_text("|") { break; }
        }
        self.make(NodeForm.or_pattern(OrPatternAst { patterns }), start)
    }
    def parse_list() -> Vec<NodeId>? {
        let patterns = Vec<NodeId>.new();
        guard let first = self.parse_pattern() else { return nil; }
        patterns.push(first);
        while self.match_text(",") {
            guard let next = self.parse_pattern() else { return nil; }
            patterns.push(next);
        }
        patterns
    }
    def parse_primary() -> NodeId? {
        let token = self.current();
        let start = token.span;
        if self.match_text("_") { return self.make(NodeForm.wildcard_pattern(), start); }
        if let form = literal_form(token) {
            self.take();
            let literal = self.make(form, start);
            return self.make(NodeForm.literal_pattern(LiteralPatternAst { value: literal }), start);
        }
        if self.match_text(".") {
            if !self.at_identifier() { self.fail("case name"); return nil; }
            let case_name = self.take();
            let payload = Vec<NodeId>.new();
            if self.match_text("(") {
                if !self.current().text.equals(")") {
                    guard let values = self.parse_list() else { return nil; }
                    for value in values { payload.push(value); }
                }
                if !self.expect(")") { return nil; }
            }
            return self.make(NodeForm.enum_case_pattern(EnumCasePatternAst { case_name, payload }), start);
        }
        if self.match_text("(") {
            guard let patterns = self.parse_list() else { return nil; }
            if !self.expect(")") { return nil; }
            let elements = Vec<(String?, NodeId)>.new();
            let label: String? = nil;
            for pattern in patterns { elements.push((label, pattern)); }
            return self.make(NodeForm.tuple_pattern(TuplePatternAst { elements }), start);
        }
        if self.at_identifier() {
            var binding: String? = nil;
            if (token.text.equals("let") || token.text.equals("var")) && self.next_identifier() {
                binding = self.take();
            }
            let name = self.take();
            return self.make(NodeForm.identifier_pattern(IdentifierPatternAst { name, binding }), start);
        }
        self.fail("pattern");
        nil
    }
}

pub def parse_pattern_prefix(tokens: Vec<LexToken>, arena: AstArena,
                             start_index: i32 = 0) -> PatternParseResult {
    let cursor = PatternCursor {
        tokens, arena, index: start_index, end_line: 0, end_column: 0, error: nil
    };
    let pattern = cursor.parse_pattern();
    PatternParseResult { pattern, next_index: cursor.index, error: cursor.error }
}

pub def parse_pattern_text(source: String, arena: AstArena) -> PatternParseResult {
    let lexed = tokenize(source);
    if let problem = lexed.error {
        return PatternParseResult { pattern: nil, next_index: 0, error: problem.message };
    }
    let result = parse_pattern_prefix(lexed.tokens, arena);
    if let problem = result.error { return result; }
    if result.next_index < lexed.tokens.len() - 1 {
        return PatternParseResult { pattern: nil, next_index: result.next_index,
                                    error: "unexpected token after pattern" };
    }
    result
}
