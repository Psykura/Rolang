// Recursive-descent parser for type syntax.
// The declaration parser shares this token cursor and AstArena.
pub import "lexer.rl"
pub import "ast.rl"

pub struct TypeParseResult {
    pub let type_node: NodeId?;
    pub let next_index: i32;
    pub let remaining: String;
    pub let error: SyntaxError?;
}

struct TypeCursor {
    let tokens: Vec<LexToken>;
    let arena: AstArena;
    var index: i32;
    var fragment: String;
    var fragment_offset: i32;
    var end_line: i32;
    var end_column: i32;
    var error: SyntaxError?;

    def current() -> LexToken {
        if self.index < self.tokens.len() { return self.tokens[self.index]; }
        self.tokens[self.tokens.len() - 1]
    }
    def spelling() -> String {
        if self.fragment.len() > 0 { return self.fragment; }
        self.current().text
    }
    def next_spelling() -> String {
        if self.fragment.len() > 0 { return ""; }
        if self.index + 1 < self.tokens.len() { return self.tokens[self.index + 1].text; }
        ""
    }
    def at_identifier() -> Bool {
        if self.fragment.len() > 0 { return false; }
        switch self.current().kind { case .identifier: true; default: false; }
    }
    def take() -> String {
        let value = self.spelling();
        let token = self.current();
        self.end_line = token.span.end_line;
        self.end_column = token.span.end_column;
        self.fragment = "";
        self.fragment_offset = 0;
        self.index += 1;
        value
    }
    def match_text(wanted: String) -> Bool {
        let value = self.spelling();
        if value.equals(wanted) {
            self.take();
            return true;
        }
        // Earley's contextual lexer splits a shift/assignment token into
        // generic closers when the grammar expects `>`.
        if wanted.equals(">") && value.starts_with(">") && value.len() > 1 {
            if self.fragment.len() == 0 { self.fragment = self.current().text; }
            self.fragment = self.fragment.substring(1, (self.fragment.len() as i32) - 1);
            self.fragment_offset += 1;
            self.end_line = self.current().span.line;
            self.end_column = self.current().span.column + self.fragment_offset;
            return true;
        }
        false
    }
    def fail(expected: String) -> Void {
        if let previous = self.error { return; }
        let found = self.spelling();
        let token = self.current();
        self.error = SyntaxError.expected(expected, found, Span.new(token.span.line, token.span.column + self.fragment_offset, token.span.end_line, token.span.end_column));
    }
    def expect(wanted: String) -> Bool {
        if self.match_text(wanted) { return true; }
        self.fail(f"'{wanted}'");
        false
    }
    def make(form: NodeForm, start_line: i32, start_column: i32) -> NodeId {
        self.arena.add(form, Span.new(start_line, start_column, self.end_line, self.end_column))
    }

    def parse_type() -> NodeId? {
        let start = self.current().span;
        guard let base = self.parse_primary() else { return nil; }
        var result = base;
        while true {
            var depth = 0;
            if self.match_text("?") { depth = 1; }
            else if self.spelling().equals("??") && self.closes_type(self.next_spelling()) { self.take(); depth = 2; }
            if depth == 0 { break; }
            for level in 0..<depth {
                result = self.make(NodeForm.optional_type(OptionalTypeAst { inner: result }), start.line, start.column);
            }
        }
        result
    }
    // The lexer reads `T??` as the coalescing operator; it is a nested optional
    // only where the type ends, so `value as T ?? fallback` still coalesces.
    def closes_type(next: String) -> Bool {
        switch next {
            case "", "=", ",", ")", "]", ">", ">>", "{", "}", ";", ":", "?", "??", "where", "->": true;
            default: false;
        }
    }

    def parse_primary() -> NodeId? {
        let token = self.current();
        let start_line = token.span.line;
        let start_column = token.span.column + self.fragment_offset;
        if self.match_text("[") {
            guard let first = self.parse_type() else { return nil; }
            if self.match_text(":") {
                guard let value = self.parse_type() else { return nil; }
                if !self.expect("]") { return nil; }
                return self.make(NodeForm.dict_type(DictTypeAst { key: first, value }),
                                 start_line, start_column);
            }
            if !self.expect("]") { return nil; }
            return self.make(NodeForm.array_type(ArrayTypeAst { element: first }),
                             start_line, start_column);
        }
        if self.spelling().equals("(") { return self.parse_parenthesized(); }
        if self.spelling().equals("any") {
            self.take();
            guard let protocol = self.parse_named() else { return nil; }
            return self.make(NodeForm.any_type(AnyTypeAst { protocol }), start_line, start_column);
        }
        if self.spelling().equals("RawPtr") {
            self.take();
            return self.make(NodeForm.pointer_type(), start_line, start_column);
        }
        if self.at_identifier() {
            let name = self.spelling();
            if builtin_name(name) {
                self.take();
                return self.make(NodeForm.builtin_type(BuiltinTypeAst { name }), start_line, start_column);
            }
            return self.parse_named();
        }
        self.fail("type");
        nil
    }

    def parse_named() -> NodeId? {
        if !self.at_identifier() { self.fail("type name"); return nil; }
        let start = self.current().span;
        var name = self.take();
        let module_path = Vec<String>.new();
        while self.match_text(".") {
            if !self.at_identifier() { self.fail("identifier"); return nil; }
            module_path.push(name);
            name = self.take();
        }
        let generic_args = Vec<NodeId>.new();
        if self.match_text("<") {
            guard let first = self.parse_type() else { return nil; }
            generic_args.push(first);
            while self.match_text(",") {
                guard let argument = self.parse_type() else { return nil; }
                generic_args.push(argument);
            }
            if !self.expect(">") { return nil; }
        }
        self.make(NodeForm.named_type(NamedTypeAst { name, module_path, generic_args }),
                  start.line, start.column)
    }

    def parse_parenthesized() -> NodeId? {
        let start = self.current().span;
        self.take();
        let elements = Vec<(String?, NodeId)>.new();
        var has_label = false;
        var had_comma = false;
        if !self.match_text(")") {
            while true {
                var label: String? = nil;
                if self.at_identifier() && self.next_spelling().equals(":") {
                    label = self.take();
                    self.take();
                    has_label = true;
                }
                guard let element = self.parse_type() else { return nil; }
                elements.push((label, element));
                if self.match_text(")") { break; }
                if !self.expect(",") { return nil; }
                had_comma = true;
            }
        }
        var is_async = false;
        if self.match_text("async") { is_async = true; }
        if self.match_text("->") {
            if has_label { self.fail("unlabeled function parameter"); return nil; }
            guard let return_type = self.parse_type() else { return nil; }
            let params = Vec<NodeId>.new();
            for element in elements { params.push(element.1); }
            return self.make(NodeForm.function_type(FunctionTypeAst {
                params, return_type, is_async
            }), start.line, start.column);
        }
        if is_async { self.fail("'->'"); return nil; }
        if elements.len() == 1 && !had_comma && !has_label { return elements[0].1; }
        if elements.len() >= 2 {
            return self.make(NodeForm.tuple_type(TupleTypeAst { elements }),
                             start.line, start.column);
        }
        self.fail("tuple or function type");
        nil
    }
}

def builtin_name(name: String) -> Bool {
    switch name {
        case "i8", "i16", "i32", "i64", "u8", "u16", "u32", "u64",
             "f32", "f64", "Bool", "Void": true;
        default: false;
    }
}

pub def parse_type_prefix(tokens: Vec<LexToken>, arena: AstArena,
                          start_index: i32 = 0) -> TypeParseResult {
    let cursor = TypeCursor {
        tokens, arena, index: start_index, fragment: "", fragment_offset: 0,
        end_line: 0, end_column: 0, error: nil
    };
    let type_node = cursor.parse_type();
    TypeParseResult {
        type_node, next_index: cursor.index, remaining: cursor.fragment,
        error: cursor.error
    }
}

// `type_name` is a distinct grammar production: built-in spellings are
// identifiers here (e.g. the syntactically valid `i32 {}` struct literal).
pub def parse_named_type_prefix(tokens: Vec<LexToken>, arena: AstArena,
                                start_index: i32 = 0) -> TypeParseResult {
    let cursor = TypeCursor {
        tokens, arena, index: start_index, fragment: "", fragment_offset: 0,
        end_line: 0, end_column: 0, error: nil
    };
    let type_node = cursor.parse_named();
    TypeParseResult {
        type_node, next_index: cursor.index, remaining: cursor.fragment,
        error: cursor.error
    }
}
