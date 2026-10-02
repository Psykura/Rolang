// Shared recursive syntax core for expressions and statements, including
// lambda bodies and interpolation of lexer-provided string tokens.
pub import "literal_parser.rl"
pub import "type_parser.rl"
pub import "pattern_parser.rl"

pub struct ExpressionParseResult {
    pub let expression: NodeId?;
    pub let next_index: i32;
    pub let remaining: String;
    pub let error: String?;
}

def expression_before(tokens: Vec<LexToken>, arena: AstArena,
                      start: i32, end: i32) -> ExpressionParseResult {
    let prefix = Vec<LexToken>.new();
    for position in start..<end { prefix.push(tokens[position]); }
    let limit = tokens[end];
    prefix.push(LexToken {
        kind: LexKind.eof(), text: "", span: limit.span,
        byte_start: limit.byte_start, byte_end: limit.byte_start
    });
    parse_expression_prefix(prefix, arena)
}

def scalar_binary_at(level: i32, op: String) -> Bool {
    switch level {
        case 0: op.equals("??");
        case 1: op.equals("||");
        case 2: op.equals("&&");
        case 5: op.equals("|");
        case 6: op.equals("^");
        case 7: op.equals("&");
        case 8: op.equals("<<") || op.equals(">>");
        case 9: op.equals("+") || op.equals("-");
        case 10: op.equals("*") || op.equals("/") || op.equals("%");
        default: false;
    }
}

def scalar_comparison(op: String) -> Bool {
    switch op {
        case "==", "!=", "<", "<=", ">", ">=": true;
        default: false;
    }
}

def scalar_prefix(op: String) -> Bool {
    switch op {
        case "!", "-", "+", "~", "await", "spawn", "try": true;
        default: false;
    }
}

pub def continues_condition_expression(word: String) -> Bool {
    switch word {
        case "{", ".", "?.", "(", "[", "?", "??", "||", "&&", "==", "!=",
             "<", "<=", ">", ">=", "..", "..=", "|", "^", "&", "<<", ">>",
             "+", "-", "*", "/", "%", "as", "as?", "as!", "is": true;
        default: false;
    }
}

// `(` at `index` starts a closure when its matching `)` is followed by `->`.
def arrow_lambda_ahead(tokens: Vec<LexToken>, index: i32) -> Bool {
    var depth = 0; var look = index;
    while look < tokens.len() {
        let word = tokens[look].text;
        if word.equals("(") || word.equals("[") { depth += 1; }
        else if word.equals(")") || word.equals("]") { depth -= 1; if depth == 0 { return look + 1 < tokens.len() && tokens[look + 1].text.equals("->"); } }
        look += 1;
    }
    false
}
// Keywords are contextual identifiers in the reference grammar. Only treat
// `switch` as syntax when a body follows its scrutinee, rather than rejecting
// expressions such as `switch + 1` or a function named `switch`.
def braced_switch_ahead(tokens: Vec<LexToken>, index: i32) -> Bool {
    // A type named `switch` can introduce a struct literal. A switch
    // scrutinee cannot start with generic type arguments.
    if index + 1 < tokens.len() && tokens[index + 1].text.equals("<") { return false; }
    var depth = 0; var look = index + 1;
    while look < tokens.len() {
        let word = tokens[look].text;
        if depth == 0 {
            // An immediate brace belongs to a struct literal of a type named `switch`.
            if word.equals("{") { return look > index + 1; }
            if is_assignment_operator(word) { return false; }
            if word.equals(";") || word.equals("}") || word.equals(")") || word.equals("]") { return false; }
        }
        if word.equals("(") || word.equals("[") { depth += 1; }
        else if word.equals(")") || word.equals("]") { depth -= 1; }
        look += 1;
    } false
}

pub def promote_tail_switch(arena: AstArena, body: Vec<NodeId>) -> Void {
    if body.len() == 0 { return; }
    let last_index = body.len() - 1;
    guard let node = arena.get(body[last_index]) else { return; }
    switch node.form {
        case .switch_stmt(let data):
            if data.cases.len() == 0 { return; }
            for branch_id in data.cases {
                guard let branch = arena.get(branch_id) else { return; }
                switch branch.form {
                    case .switch_case(let case_data):
                        if case_data.body.len() != 1 { return; }
                        guard let item = arena.get(case_data.body[0]) else { return; }
                        switch item.form {
                            case .expr_stmt: {}
                            default: return;
                        }
                    default: return;
                }
            }
            let value = arena.add(NodeForm.switch_expr(SwitchExprAst {
                value: data.value, cases: data.cases
            }), node.span);
            body[last_index] = arena.add(NodeForm.return_stmt(ReturnStmtAst {
                value, implicit: true
            }));
        default: {}
    }
}

def template_position(token: LexToken, offset: i32) -> (i32, i32) {
    var line = token.span.line;
    var column = token.span.column;
    for index in 0..<offset {
        let byte = token.text.byte_at(index);
        if byte == 10 { line += 1; column = 1; }
        else if byte < 128 || byte >= 192 { column += 1; }
    }
    (line, column)
}

def template_span(token: LexToken, start: i32, end: i32) -> Span {
    let first = template_position(token, start);
    var last = template_position(token, end);
    if end > start && token.text.byte_at(end - 1) == 10 {
        let before_newline = template_position(token, end - 1);
        last = (before_newline.0, before_newline.1 + 1);
    }
    Span.new(first.0, first.1, last.0, last.1)
}

def template_whitespace(raw: String) -> Bool {
    for index in 0..<(raw.len() as i32) {
        let byte = raw.byte_at(index);
        if byte != 9 && byte != 10 && byte != 13 && byte != 32 { return false; }
    }
    true
}

def rebase_template_span(local: Span, origin: (i32, i32)) -> Span {
    var column = local.column;
    var end_column = local.end_column;
    if local.line == 1 { column += origin.1 - 1; }
    if local.end_line == 1 { end_column += origin.1 - 1; }
    Span.new(origin.0 + local.line - 1, column,
             origin.0 + local.end_line - 1, end_column)
}

def template_expression_end(raw: String, start: i32, limit: i32) -> i32 {
    var depth = 1;
    var index = start;
    while index < limit {
        let byte = raw.byte_at(index);
        if byte == 34 || byte == 39 {
            let quote = byte;
            let triple = quote == 34 && index + 2 < limit &&
                         raw.byte_at(index + 1) == 34 && raw.byte_at(index + 2) == 34;
            if triple { index += 3; } else { index += 1; }
            while index < limit {
                let current = raw.byte_at(index);
                if current == 92 { index += 2; continue; }
                if current == quote {
                    if !triple { index += 1; break; }
                    if index + 2 < limit && raw.byte_at(index + 1) == quote &&
                       raw.byte_at(index + 2) == quote { index += 3; break; }
                }
                index += 1;
            }
            continue;
        }
        if byte == 47 && index + 1 < limit && raw.byte_at(index + 1) == 47 {
            index += 2;
            while index < limit && raw.byte_at(index) != 10 { index += 1; }
            continue;
        }
        if byte == 47 && index + 1 < limit && raw.byte_at(index + 1) == 42 {
            index += 2;
            while index + 1 < limit &&
                  !(raw.byte_at(index) == 42 && raw.byte_at(index + 1) == 47) { index += 1; }
            index += 2;
            continue;
        }
        if byte == 123 { depth += 1; }
        if byte == 125 {
            depth -= 1;
            if depth == 0 { return index; }
        }
        index += 1;
    }
    -1
}

struct ExpressionCursor {
    let tokens: Vec<LexToken>;
    let arena: AstArena;
    var index: i32;
    var fragment: String;
    var fragment_offset: i32;
    var end_line: i32;
    var end_column: i32;
    var error: String?;

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
        if value.equals(wanted) { self.take(); return true; }
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
        let token = self.current();
        self.error = f"expected {expected} at {token.span.line}:{token.span.column + self.fragment_offset}, found '{self.spelling()}'";
    }
    def expect(wanted: String) -> Bool {
        if self.match_text(wanted) { return true; }
        self.fail(f"'{wanted}'");
        false
    }
    def make(form: NodeForm, start: Span) -> NodeId {
        self.arena.add(form, Span.new(start.line, start.column, self.end_line, self.end_column))
    }
    def finish(id: NodeId, start: Span) -> NodeId {
        if let node = self.arena.get(id) {
            node.span = Span.new(start.line, start.column, self.end_line, self.end_column);
        }
        id
    }
    def parse_type() -> NodeId? {
        if self.fragment.len() > 0 { self.fail("type"); return nil; }
        self.accept_type_result(parse_type_prefix(self.tokens, self.arena, self.index))
    }
    def parse_named_type() -> NodeId? {
        if self.fragment.len() > 0 { self.fail("type name"); return nil; }
        self.accept_type_result(parse_named_type_prefix(self.tokens, self.arena, self.index))
    }
    def accept_type_result(result: TypeParseResult) -> NodeId? {
        if let problem = result.error { self.error = problem; return nil; }
        self.index = result.next_index;
        self.fragment = result.remaining;
        self.fragment_offset = 0;
        if self.fragment.len() > 0 {
            self.fragment_offset = (self.current().text.len() as i32) - (self.fragment.len() as i32);
        }
        if let id = result.type_node {
            if let node = self.arena.get(id) {
                if let span = node.span {
                    self.end_line = span.end_line;
                    self.end_column = span.end_column;
                }
            }
        }
        result.type_node
    }

    def parse_expression() -> NodeId? {
        let start = self.current().span;
        guard let condition = self.parse_level(0) else { return nil; }
        if !self.match_text("?") { return condition; }
        guard let then_expr = self.parse_expression() else { return nil; }
        if !self.expect(":") { return nil; }
        guard let else_expr = self.parse_expression() else { return nil; }
        self.make(NodeForm.ternary_op(TernaryOpAst { condition, then_expr, else_expr }), start)
    }
    def parse_level(level: i32) -> NodeId? {
        if level == 3 { return self.parse_comparison(); }
        if level == 4 { return self.parse_range(); }
        if level == 11 { return self.parse_prefix(); }
        let start = self.current().span;
        guard let first = self.parse_level(level + 1) else { return nil; }
        var result = first;
        var combined = false;
        while scalar_binary_at(level, self.spelling()) {
            let op = self.take();
            guard let right = self.parse_level(level + 1) else { return nil; }
            result = self.arena.add(NodeForm.binary_op(BinaryOpAst { left: result, op, right }));
            combined = true;
        }
        if combined { return self.finish(result, start); }
        result
    }
    def parse_comparison() -> NodeId? {
        let start = self.current().span;
        guard let first = self.parse_range() else { return nil; }
        var result = first;
        var combined = false;
        while true {
            let op = self.spelling();
            if scalar_comparison(op) {
                self.take();
                guard let right = self.parse_range() else { return nil; }
                result = self.arena.add(NodeForm.binary_op(BinaryOpAst { left: result, op, right }));
            } else if op.equals("as") || op.equals("as?") || op.equals("as!") {
                self.take();
                guard let target_type = self.parse_type() else { return nil; }
                var kind = "safe";
                if op.equals("as?") { kind = "optional"; }
                if op.equals("as!") { kind = "forced"; }
                result = self.arena.add(NodeForm.cast(CastAst { expr: result, target_type, kind }));
            } else if op.equals("is") {
                self.take();
                guard let checked_type = self.parse_type() else { return nil; }
                result = self.arena.add(NodeForm.type_check(TypeCheckAst { expr: result, checked_type }));
            } else { break; }
            combined = true;
        }
        if combined { return self.finish(result, start); }
        result
    }
    // `a..<b` and `a...b`; `..<b`, `...b` start at 0 and `a...` runs to the i32 maximum,
    // which slicing clamps to the length.
    def parse_range() -> NodeId? {
        let start = self.current().span;
        var first: NodeId? = nil;
        if self.spelling().equals("..<") || self.spelling().equals("...") {
            first = self.arena.add(NodeForm.literal(LiteralAst { value: LiteralValue.integer("0"), kind: "int" }));
        } else {
            guard let lower = self.parse_level(5) else { return nil; }
            first = lower;
        }
        let op = self.spelling();
        if !op.equals("..<") && !op.equals("...") { return first; }
        self.take();
        var last: NodeId? = nil;
        let next = self.spelling();
        if op.equals("...") && (next.equals("]") || next.equals(")") || next.equals(",") || next.equals(";") || next.equals("{") || next.equals("}") || next.len() == 0) {
            last = self.arena.add(NodeForm.literal(LiteralAst { value: LiteralValue.integer("2147483647"), kind: "int" }));
            let open = self.arena.add(NodeForm.literal(LiteralAst { value: LiteralValue.boolean(false), kind: "bool" }));
            return self.range_literal(first, last, open, start);
        }
        guard let upper = self.parse_level(5) else { return nil; }
        last = upper;
        let inclusive = self.arena.add(NodeForm.literal(LiteralAst {
            value: LiteralValue.boolean(op.equals("...")), kind: "bool"
        }));
        self.range_literal(first, last, inclusive, start)
    }
    def range_literal(first: NodeId?, last: NodeId?, inclusive: NodeId, start: Span) -> NodeId {
        let type_name = self.arena.add(NodeForm.named_type(NamedTypeAst {
            name: "IndexRange", module_path: Vec<String>.new(), generic_args: Vec<NodeId>.new()
        }));
        let arguments = Vec<NodeId>.new();
        arguments.push(self.arena.add(NodeForm.argument(ArgumentAst { label: "start", value: first })));
        arguments.push(self.arena.add(NodeForm.argument(ArgumentAst { label: "end", value: last })));
        arguments.push(self.arena.add(NodeForm.argument(ArgumentAst { label: "inclusive", value: inclusive })));
        self.make(NodeForm.struct_literal(StructLiteralAst { type_name, arguments }), start)
    }
    def parse_prefix() -> NodeId? {
        let start = self.current().span;
        let op = self.spelling();
        if scalar_prefix(op) {
            self.take();
            guard let operand = self.parse_prefix() else { return nil; }
            return self.make(NodeForm.unary_op(UnaryOpAst { op, operand }), start);
        }
        self.parse_postfix()
    }
    // A postfix `?` and a ternary `?` share a token. Only a colon at the
    // current delimiter depth makes it the ternary operator.
    def ternary_question() -> Bool {
        let next = self.next_spelling();
        if next.equals("") || next.equals("?") || next.equals(":") ||
           next.equals(")") || next.equals("]") || next.equals("}") ||
           next.equals(",") || next.equals(";") { return false; }
        // A binary operator cannot begin the true arm of a ternary. In a
        // switch guard the later colon terminates the guard, so it must not
        // turn `read()? > 0` (or `read()? && ready`) into a ternary.
        if scalar_comparison(next) || scalar_binary_at(0, next) ||
           scalar_binary_at(1, next) || scalar_binary_at(2, next) ||
           scalar_binary_at(5, next) || scalar_binary_at(6, next) ||
           scalar_binary_at(7, next) || scalar_binary_at(8, next) ||
           scalar_binary_at(10, next) { return false; }
        var depth = 0;
        var look = self.index + 1;
        var questions = 0;
        var colons = 0;
        while look < self.tokens.len() {
            let word = self.tokens[look].text;
            if word.equals("(") || word.equals("[") || word.equals("{") { depth += 1; }
            else if word.equals(")") || word.equals("]") || word.equals("}") {
                if depth == 0 { break; }
                depth -= 1;
            } else if depth == 0 {
                if word.equals("?") { questions += 1; }
                if word.equals(":") { colons += 1; }
                if word.equals(",") || word.equals(";") { break; }
            }
            look += 1;
        }
        if colons == 0 { return false; }
        if scalar_prefix(next) && questions > 0 && colons <= questions { return false; }
        true
    }
    def parse_arguments() -> Vec<NodeId>? {
        if !self.expect("(") { return nil; }
        let arguments = Vec<NodeId>.new();
        if self.match_text(")") { return arguments; }
        while true {
            let start = self.current().span;
            var label: String? = nil;
            if self.at_identifier() && self.next_spelling().equals(":") {
                label = self.take();
                self.take();
            }
            guard let value = self.parse_expression() else { return nil; }
            arguments.push(self.make(NodeForm.argument(ArgumentAst { label, value }), start));
            if self.match_text(")") { break; }
            if !self.expect(",") { return nil; }
        }
        arguments
    }
    def parse_indices() -> Vec<NodeId>? {
        if !self.expect("[") { return nil; }
        let indices = Vec<NodeId>.new();
        guard let first = self.parse_expression() else { return nil; }
        indices.push(first);
        while self.match_text(",") {
            guard let next = self.parse_expression() else { return nil; }
            indices.push(next);
        }
        if !self.expect("]") { return nil; }
        indices
    }
    def parse_postfix() -> NodeId? {
        let start = self.current().span;
        guard let first = self.parse_primary() else { return nil; }
        var result = first;
        var combined = false;
        while true {
            if self.spelling().equals("(") {
                guard let arguments = self.parse_arguments() else { return nil; }
                result = self.arena.add(NodeForm.call(CallAst {
                    callee: result, arguments, is_interpolation: false
                }));
            } else if self.match_text(".") {
                let token = self.current();
                var valid = self.at_identifier();
                switch token.kind { case .integer: valid = true; default: {} }
                if !valid { self.fail("member name"); return nil; }
                let member = self.take();
                result = self.arena.add(NodeForm.member_access(MemberAccessAst { object: result, member }));
            } else if self.match_text("?.") {
                if !self.at_identifier() { self.fail("optional member name"); return nil; }
                let member = self.take();
                var suffix: AstOptionalSuffix? = nil;
                if self.spelling().equals("(") {
                    guard let arguments = self.parse_arguments() else { return nil; }
                    suffix = AstOptionalSuffix.call(arguments);
                } else if self.spelling().equals("[") {
                    guard let indices = self.parse_indices() else { return nil; }
                    suffix = AstOptionalSuffix.index(indices);
                }
                result = self.arena.add(NodeForm.optional_chain(OptionalChainAst {
                    object: result, member, suffix
                }));
            } else if self.spelling().equals("[") {
                guard let indices = self.parse_indices() else { return nil; }
                result = self.arena.add(NodeForm.subscript(SubscriptAst { object: result, indices }));
            } else if self.spelling().equals("?") && !self.ternary_question() {
                self.take();
                result = self.arena.add(NodeForm.try_expr(TryExprAst { value: result }));
            } else { break; }
            combined = true;
        }
        if combined { return self.finish(result, start); }
        result
    }
    def parse_intrinsic(name: String, start: Span) -> NodeId? {
        self.take();
        if !self.expect("(") { return nil; }
        guard let type_arg = self.parse_type() else { return nil; }
        if !self.expect(")") { return nil; }
        switch name {
            case "size_of": self.make(NodeForm.size_of_expr(SizeOfExprAst { type_arg }), start);
            case "type_id": self.make(NodeForm.type_id_expr(TypeIdExprAst { type_arg }), start);
            case "align_of": self.make(NodeForm.align_of_expr(AlignOfExprAst { type_arg }), start);
            case "drop_of": self.make(NodeForm.drop_of_expr(DropOfExprAst { type_arg }), start);
            default: self.make(NodeForm.clone_of_expr(CloneOfExprAst { type_arg }), start);
        }
    }
    def parse_tuple_element() -> (String?, NodeId)? {
        var label: String? = nil;
        if self.at_identifier() && self.next_spelling().equals(":") {
            label = self.take();
            self.take();
        }
        guard let value = self.parse_expression() else { return nil; }
        (label, value)
    }
    def parse_parenthesized(start: Span) -> NodeId? {
        self.take();
        guard let first = self.parse_tuple_element() else { return nil; }
        if !self.match_text(",") {
            if let label = first.0 { self.fail("tuple element"); return nil; }
            if !self.expect(")") { return nil; }
            return first.1;
        }
        let elements = Vec<(String?, NodeId)>.new();
        elements.push(first);
        guard let second = self.parse_tuple_element() else { return nil; }
        elements.push(second);
        while self.match_text(",") {
            guard let next = self.parse_tuple_element() else { return nil; }
            elements.push(next);
        }
        if !self.expect(")") { return nil; }
        self.make(NodeForm.tuple_expr(TupleExprAst { elements }), start)
    }
    def parse_collection(start: Span) -> NodeId? {
        self.take();
        if self.match_text("]") {
            return self.make(NodeForm.array_literal(ArrayLiteralAst {
                elements: Vec<NodeId>.new()
            }), start);
        }
        if self.match_text(":") {
            if !self.expect("]") { return nil; }
            return self.make(NodeForm.dict_literal(DictLiteralAst {
                entries: Vec<(NodeId, NodeId)>.new()
            }), start);
        }
        guard let first = self.parse_expression() else { return nil; }
        if self.match_text(":") {
            let entries = Vec<(NodeId, NodeId)>.new();
            guard let value = self.parse_expression() else { return nil; }
            entries.push((first, value));
            while self.match_text(",") {
                guard let key = self.parse_expression() else { return nil; }
                if !self.expect(":") { return nil; }
                guard let entry_value = self.parse_expression() else { return nil; }
                entries.push((key, entry_value));
            }
            if !self.expect("]") { return nil; }
            return self.make(NodeForm.dict_literal(DictLiteralAst { entries }), start);
        }
        let elements = Vec<NodeId>.new();
        elements.push(first);
        while self.match_text(",") {
            guard let next = self.parse_expression() else { return nil; }
            elements.push(next);
        }
        if !self.expect("]") { return nil; }
        self.make(NodeForm.array_literal(ArrayLiteralAst { elements }), start)
    }
    def template_text(token: LexToken, start: i32, end: i32,
                      trailing_gap: Bool = false) -> NodeId {
        let raw = token.text.substring(start, end - start);
        let decoded = unescape_literal(raw.replace("{{", "{").replace("}}", "}"));
        var span: Span? = template_span(token, start, end);
        if trailing_gap && template_whitespace(raw) { span = nil; }
        self.arena.add(NodeForm.literal(LiteralAst {
            value: LiteralValue.text(decoded), kind: "string"
        }), span)
    }
    def template_value(token: LexToken, start: i32, end: i32) -> NodeId? {
        let raw = token.text.substring(start, end - start);
        let lexed = tokenize(raw);
        if let problem = lexed.error { self.error = problem.message; return nil; }
        let origin = template_position(token, start);
        let shifted = Vec<LexToken>.new();
        for piece in lexed.tokens {
            shifted.push(LexToken {
                kind: piece.kind, text: piece.text,
                span: rebase_template_span(piece.span, origin),
                byte_start: token.byte_start + start + piece.byte_start,
                byte_end: token.byte_start + start + piece.byte_end
            });
        }
        let result = parse_expression_prefix(shifted, self.arena);
        if let problem = result.error { self.error = problem; return nil; }
        if result.remaining.len() > 0 || result.next_index != shifted.len() - 1 {
            self.fail("interpolation expression");
            return nil;
        }
        guard let value = result.expression else { self.fail("interpolation expression"); return nil; }
        guard let node = self.arena.get(value) else { self.fail("interpolation expression"); return nil; }
        let member = self.arena.add(NodeForm.member_access(MemberAccessAst {
            object: value, member: "to_string"
        }), node.span);
        self.arena.add(NodeForm.call(CallAst {
            callee: member, arguments: Vec<NodeId>.new(), is_interpolation: true
        }), node.span)
    }
    def combine_template(parts: Vec<NodeId>, start: i32, end: i32) -> NodeId {
        if end - start == 1 { return parts[start]; }
        let middle = (start + end) / 2;
        let left = self.combine_template(parts, start, middle);
        let right = self.combine_template(parts, middle, end);
        var span: Span? = nil;
        if let first = self.arena.get(parts[start]) { span = first.span; }
        self.arena.add(NodeForm.binary_op(BinaryOpAst {
            left, op: "+", right
        }), span)
    }
    def parse_template() -> NodeId? {
        let token = self.current();
        let raw = token.text;
        self.take();
        var opening = 2;
        var closing = 1;
        switch token.kind {
            case .interpolated_multiline_string: opening = 4; closing = 3;
            default: {}
        }
        let limit = (raw.len() as i32) - closing;
        let parts = Vec<NodeId>.new();
        var index = opening;
        var text_start = opening;
        while index < limit {
            let byte = raw.byte_at(index);
            if byte == 92 { index += 2; continue; }
            if (byte == 123 || byte == 125) && index + 1 < limit &&
               raw.byte_at(index + 1) == byte { index += 2; continue; }
            if byte == 123 {
                if index > text_start { parts.push(self.template_text(token, text_start, index)); }
                let finish = template_expression_end(raw, index + 1, limit);
                if finish < 0 { self.fail("closing interpolation brace"); return nil; }
                guard let value = self.template_value(token, index + 1, finish) else { return nil; }
                parts.push(value);
                index = finish + 1;
                text_start = index;
                continue;
            }
            if byte == 125 { self.fail("escaped closing brace"); return nil; }
            index += 1;
        }
        if text_start < limit {
            parts.push(self.template_text(token, text_start, limit, parts.len() > 0));
        }
        if parts.len() == 0 {
            return self.arena.add(NodeForm.literal(LiteralAst {
                value: LiteralValue.text(""), kind: "string"
            }), token.span);
        }
        self.combine_template(parts, 0, parts.len())
    }
    def parse_switch_value() -> NodeId? {
        var boundary = self.index;
        var nesting = 0;
        while boundary < self.tokens.len() {
            let word = self.tokens[boundary].text;
            if word.equals("{") && nesting == 0 {
                var after = boundary + 1;
                var braces = 1;
                while after < self.tokens.len() && braces > 0 {
                    let nested = self.tokens[after].text;
                    if nested.equals("{") { braces += 1; }
                    else if nested.equals("}") { braces -= 1; }
                    after += 1;
                }
                if braces != 0 { break; }
                let starts_case = self.tokens[boundary + 1].text.equals("case") ||
                                  self.tokens[boundary + 1].text.equals("default");
                if after >= self.tokens.len() ||
                   (starts_case && !self.tokens[after].text.equals("{")) ||
                   !continues_condition_expression(self.tokens[after].text) { break; }
                boundary = after;
                continue;
            }
            if word.equals("(") || word.equals("[") { nesting += 1; }
            else if word.equals(")") || word.equals("]") { nesting -= 1; }
            boundary += 1;
        }
        if boundary >= self.tokens.len() { self.fail("switch body"); return nil; }
        self.parse_expression_until(boundary, "switch value")
    }
    // Parses the tokens from the cursor up to `boundary` as one complete expression.
    def parse_expression_until(boundary: i32, what: String) -> NodeId? {
        let limit = self.tokens[boundary];
        let prefix = Vec<LexToken>.new();
        for position in 0..<boundary { prefix.push(self.tokens[position]); }
        prefix.push(LexToken {
            kind: LexKind.eof(), text: "", span: limit.span,
            byte_start: limit.byte_start, byte_end: limit.byte_start
        });
        let result = parse_expression_prefix(prefix, self.arena, self.index);
        if let problem = result.error { self.error = problem; return nil; }
        if result.remaining.len() > 0 || result.next_index != boundary {
            self.fail(what);
            return nil;
        }
        self.index = boundary;
        let previous = self.tokens[boundary - 1].span;
        self.end_line = previous.end_line;
        self.end_column = previous.end_column;
        result.expression
    }
    // `if c { a } else if d { b } else { c }` in expression position is a chain of ternaries;
    // each branch holds exactly one expression.
    def parse_if_expr(start: Span) -> NodeId? {
        self.take();
        if self.spelling().equals("let") || self.spelling().equals("var") { self.fail("a Bool condition (`if let` is a statement; use switch for a value)"); return nil; }
        var boundary = self.index; var nesting = 0;
        while boundary < self.tokens.len() {
            let word = self.tokens[boundary].text;
            if word.equals("{") && nesting == 0 { break; }
            if word.equals("(") || word.equals("[") { nesting += 1; }
            else if word.equals(")") || word.equals("]") { nesting -= 1; }
            boundary += 1;
        }
        if boundary >= self.tokens.len() { self.fail("if expression branch"); return nil; }
        guard let condition = self.parse_expression_until(boundary, "if condition") else { return nil; }
        guard let then_expr = self.parse_if_branch() else { return nil; }
        if !self.match_text("else") { self.fail("'else' (an if expression needs both branches)"); return nil; }
        var else_expr: NodeId? = nil;
        if self.spelling().equals("if") { else_expr = self.parse_if_expr(self.current().span); }
        else { else_expr = self.parse_if_branch(); }
        guard let otherwise = else_expr else { return nil; }
        self.make(NodeForm.ternary_op(TernaryOpAst { condition, then_expr, else_expr: otherwise }), start)
    }
    def parse_if_branch() -> NodeId? {
        if !self.expect("{") { return nil; }
        guard let value = self.parse_expression() else { return nil; }
        if !self.spelling().equals("}") { self.fail("'}' (if expression branches hold a single expression)"); return nil; }
        self.take();
        value
    }
    def parse_switch_pattern() -> NodeId? {
        let result = parse_pattern_prefix(self.tokens, self.arena, self.index);
        if let problem = result.error { self.error = problem; return nil; }
        self.index = result.next_index;
        if self.index > 0 {
            let previous = self.tokens[self.index - 1].span;
            self.end_line = previous.end_line;
            self.end_column = previous.end_column;
        }
        result.pattern
    }
    def parse_switch_case() -> NodeId? {
        let start = self.current().span;
        let is_default = self.match_text("default");
        let patterns = Vec<(NodeId, NodeId?)>.new();
        if !is_default {
            if !self.expect("case") { return nil; }
            while true {
                guard let pattern = self.parse_switch_pattern() else { return nil; }
                var condition: NodeId? = nil;
                if self.match_text("where") {
                    guard let expression = self.parse_expression() else { return nil; }
                    condition = expression;
                }
                patterns.push((pattern, condition));
                if !self.match_text(",") { break; }
            }
        }
        if !self.expect(":") { return nil; }
        guard let expression = self.parse_expression() else { return nil; }
        if !self.expect(";") { return nil; }
        let body = Vec<NodeId>.new();
        body.push(self.arena.add(NodeForm.expr_stmt(ExprStmtAst { expr: expression })));
        self.make(NodeForm.switch_case(SwitchCaseAst { patterns, body, is_default }), start)
    }
    def parse_switch_expr(start: Span) -> NodeId? {
        self.take();
        guard let value = self.parse_switch_value() else { return nil; }
        if !self.expect("{") { return nil; }
        let cases = Vec<NodeId>.new();
        if self.spelling().equals("}") { self.fail("switch case"); return nil; }
        while !self.spelling().equals("}") {
            if !self.spelling().equals("case") && !self.spelling().equals("default") {
                self.fail("'case' or 'default'");
                return nil;
            }
            guard let branch = self.parse_switch_case() else { return nil; }
            cases.push(branch);
        }
        if !self.expect("}") { return nil; }
        self.make(NodeForm.switch_expr(SwitchExprAst { value, cases }), start)
    }
    def parse_lambda_expr() -> NodeId? {
        let cursor = StatementCursor {
            tokens: self.tokens, arena: self.arena, index: self.index,
            end_line: self.end_line, end_column: self.end_column, error: nil
        };
        let expression = cursor.parse_arrow_lambda();
        if let problem = cursor.error { self.error = problem; return nil; }
        self.index = cursor.index;
        self.end_line = cursor.end_line;
        self.end_column = cursor.end_column;
        expression
    }
    def typed_primary_ahead() -> Bool {
        if !self.at_identifier() { return false; }
        var depth = 0;
        var saw_generic = false;
        var look = self.index + 1;
        while look < self.tokens.len() {
            let token = self.tokens[look];
            let word = token.text;
            if depth == 0 && word.equals("{") { return true; }
            if word.equals("<") { depth += 1; saw_generic = true; }
            else if word.equals(">") { depth -= 1; }
            else if word.equals(">>") { depth -= 2; }
            else if depth == 0 {
                if word.equals(".") {
                    if saw_generic { return true; }
                } else {
                    switch token.kind {
                        case .identifier: {}
                        default: return false;
                    }
                }
            }
            if depth < 0 { return false; }
            look += 1;
        }
        false
    }
    def parse_struct_field() -> NodeId? {
        if !self.at_identifier() { self.fail("field name"); return nil; }
        let start = self.current().span;
        let name = self.take();
        var value: NodeId? = nil;
        if self.match_text(":") {
            guard let expression = self.parse_expression() else { return nil; }
            value = expression;
        } else {
            value = self.arena.add(NodeForm.identifier(IdentifierAst { name }));
        }
        self.make(NodeForm.argument(ArgumentAst { label: name, value }), start)
    }
    def parse_typed_primary(start: Span) -> NodeId? {
        guard let type_name = self.parse_named_type() else { return nil; }
        if self.match_text("{") {
            let arguments = Vec<NodeId>.new();
            if !self.match_text("}") {
                while true {
                    guard let field = self.parse_struct_field() else { return nil; }
                    arguments.push(field);
                    if self.match_text("}") { break; }
                    if !self.expect(",") { return nil; }
                    if self.match_text("}") { break; }
                }
            }
            return self.make(NodeForm.struct_literal(StructLiteralAst { type_name, arguments }), start);
        }
        if !self.expect(".") { return nil; }
        if !self.at_identifier() { self.fail("type member"); return nil; }
        let member = self.take();
        let reference = self.arena.add(NodeForm.type_reference(TypeReferenceAst { type_name }));
        self.make(NodeForm.member_access(MemberAccessAst { object: reference, member }), start)
    }
    def parse_primary() -> NodeId? {
        let token = self.current();
        let start = token.span;
        switch token.kind {
            case .interpolated_string, .interpolated_multiline_string:
                return self.parse_template();
            default: {}
        }
        if let form = literal_form(token) {
            self.take();
            return self.make(form, start);
        }
        if self.spelling().equals("(") && arrow_lambda_ahead(self.tokens, self.index) { return self.parse_lambda_expr(); }
        if self.spelling().equals("(") { return self.parse_parenthesized(start); }
        if self.spelling().equals("[") { return self.parse_collection(start); }
        if self.spelling().equals("switch") && braced_switch_ahead(self.tokens, self.index) { return self.parse_switch_expr(start); }
        if self.spelling().equals("if") { return self.parse_if_expr(start); }
        if self.spelling().equals("{") { self.fail("expression (closures are written `(params) -> { body }`)"); return nil; }
        if self.typed_primary_ahead() { return self.parse_typed_primary(start); }
        if self.at_identifier() {
            let name = self.spelling();
            if self.next_spelling().equals("(") &&
               (name.equals("size_of") || name.equals("type_id") || name.equals("align_of") ||
                name.equals("drop_of") || name.equals("clone_of")) {
                return self.parse_intrinsic(name, start);
            }
            self.take();
            return self.make(NodeForm.identifier(IdentifierAst { name }), start);
        }
        self.fail("expression");
        nil
    }
}

pub def parse_expression_prefix(tokens: Vec<LexToken>, arena: AstArena,
                                start_index: i32 = 0) -> ExpressionParseResult {
    let cursor = ExpressionCursor {
        tokens, arena, index: start_index, fragment: "", fragment_offset: 0,
        end_line: 0, end_column: 0, error: nil
    };
    let expression = cursor.parse_expression();
    ExpressionParseResult {
        expression, next_index: cursor.index, remaining: cursor.fragment, error: cursor.error
    }
}

pub def parse_scalar_expression_text(source: String, arena: AstArena) -> ExpressionParseResult {
    let lexed = tokenize(source);
    if let problem = lexed.error {
        return ExpressionParseResult { expression: nil, next_index: 0,
                                       remaining: "", error: problem.message };
    }
    let result = parse_expression_prefix(lexed.tokens, arena);
    if let problem = result.error { return result; }
    if result.remaining.len() > 0 || result.next_index < lexed.tokens.len() - 1 {
        return ExpressionParseResult {
            expression: nil, next_index: result.next_index, remaining: result.remaining,
            error: "unexpected token after expression"
        };
    }
    result
}

// Statement and expression cursors share this module because lambda bodies
// and statement expressions recursively depend on each other.
pub struct StatementParseResult {
    pub let statement: NodeId?;
    pub let next_index: i32;
    pub let error: String?;
}

def is_assignment_operator(word: String) -> Bool {
    switch word {
        case "=", "+=", "-=", "*=", "/=", "%=", "&=", "|=", "^=", "<<=", ">>=": true;
        default: false;
    }
}

struct StatementCursor {
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
    def spelling() -> String { self.current().text }
    def at_identifier() -> Bool {
        switch self.current().kind { case .identifier: true; default: false; }
    }
    def take() -> String {
        let token = self.current();
        self.end_line = token.span.end_line;
        self.end_column = token.span.end_column;
        self.index += 1;
        token.text
    }
    def match_text(wanted: String) -> Bool {
        if !self.spelling().equals(wanted) { return false; }
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
    def finish(id: NodeId, start: Span) -> NodeId {
        if let node = self.arena.get(id) {
            node.span = Span.new(start.line, start.column, self.end_line, self.end_column);
        }
        id
    }
    def accept_end() -> Void {
        if self.index <= 0 { return; }
        let span = self.tokens[self.index - 1].span;
        self.end_line = span.end_line;
        self.end_column = span.end_column;
    }
    def parse_pattern() -> NodeId? {
        let result = parse_pattern_prefix(self.tokens, self.arena, self.index);
        if let problem = result.error { self.error = problem; return nil; }
        self.index = result.next_index;
        self.accept_end();
        result.pattern
    }
    def parse_type() -> NodeId? {
        let result = parse_type_prefix(self.tokens, self.arena, self.index);
        if let problem = result.error { self.error = problem; return nil; }
        if result.remaining.len() > 0 { self.fail("complete type"); return nil; }
        self.index = result.next_index;
        self.accept_end();
        result.type_node
    }
    def parse_expression() -> NodeId? {
        let result = parse_expression_prefix(self.tokens, self.arena, self.index);
        if let problem = result.error { self.error = problem; return nil; }
        if result.remaining.len() > 0 { self.fail("complete expression"); return nil; }
        self.index = result.next_index;
        self.accept_end();
        result.expression
    }
    // Probe candidate boundaries in a separate arena. A following operator or
    // parenthesis may start the next statement, so token lookahead alone cannot
    // distinguish the body from a struct literal in the condition.
    def parse_condition_expression(delimiter: String) -> NodeId? {
        var boundary = self.index;
        var nesting = 0;
        var first_boundary = -1;
        var chosen_boundary = -1;
        while boundary < self.tokens.len() {
            let word = self.tokens[boundary].text;
            if word.equals(delimiter) && nesting == 0 {
                if !delimiter.equals("{") { break; }
                if first_boundary < 0 { first_boundary = boundary; }
                let probe = expression_before(self.tokens, AstArena.new(), self.index, boundary);
                var accepted = true;
                if let problem = probe.error { accepted = false; }
                if accepted && probe.remaining.len() == 0 &&
                   probe.next_index == boundary - self.index {
                    chosen_boundary = boundary;
                } else if chosen_boundary >= 0 { break; }
                var after = boundary + 1;
                var braces = 1;
                while after < self.tokens.len() && braces > 0 {
                    let nested = self.tokens[after].text;
                    if nested.equals("{") { braces += 1; }
                    else if nested.equals("}") { braces -= 1; }
                    after += 1;
                }
                if braces != 0 || after >= self.tokens.len() ||
                   !continues_condition_expression(self.tokens[after].text) { break; }
                boundary = after;
                continue;
            }
            if word.equals("(") || word.equals("[") { nesting += 1; }
            else if word.equals(")") || word.equals("]") { nesting -= 1; }
            boundary += 1;
        }
        if delimiter.equals("{") {
            if chosen_boundary >= 0 { boundary = chosen_boundary; }
            else if first_boundary >= 0 { boundary = first_boundary; }
        }
        if boundary >= self.tokens.len() { self.fail(f"'{delimiter}'"); return nil; }
        let result = expression_before(self.tokens, self.arena, self.index, boundary);
        if let problem = result.error { self.error = problem; return nil; }
        if result.remaining.len() > 0 || result.next_index != boundary - self.index {
            self.fail("condition expression");
            return nil;
        }
        self.index = boundary;
        self.accept_end();
        result.expression
    }
    def parse_condition(delimiter: String) -> AstCondition? {
        if self.match_text("let") {
            guard let pattern = self.parse_pattern() else { return nil; }
            if !self.expect("=") { return nil; }
            guard let value = self.parse_condition_expression(delimiter) else { return nil; }
            return AstCondition.binding(pattern, value);
        }
        guard let value = self.parse_condition_expression(delimiter) else { return nil; }
        AstCondition.expression(value)
    }
    def assignment_ahead() -> Bool {
        var depth = 0;
        var look = self.index;
        while look < self.tokens.len() {
            let word = self.tokens[look].text;
            if word.equals("(") || word.equals("[") || word.equals("{") { depth += 1; }
            else if word.equals(")") || word.equals("]") || word.equals("}") {
                if depth == 0 { return false; }
                depth -= 1;
            } else if depth == 0 {
                if is_assignment_operator(word) { return true; }
                if word.equals(";") { return false; }
            }
            look += 1;
        }
        false
    }
    def parse_indices() -> Vec<NodeId>? {
        if !self.expect("[") { return nil; }
        let indices = Vec<NodeId>.new();
        guard let first = self.parse_expression() else { return nil; }
        indices.push(first);
        while self.match_text(",") {
            guard let next = self.parse_expression() else { return nil; }
            indices.push(next);
        }
        if !self.expect("]") { return nil; }
        indices
    }
    def parse_lvalue() -> NodeId? {
        if !self.at_identifier() { self.fail("assignment target"); return nil; }
        let start = self.current().span;
        let name = self.take();
        var target = self.arena.add(NodeForm.identifier(IdentifierAst { name }));
        while true {
            if self.match_text(".") {
                let token = self.current();
                var valid = self.at_identifier();
                switch token.kind { case .integer: valid = true; default: {} }
                if !valid { self.fail("member name"); return nil; }
                let member = self.take();
                target = self.arena.add(NodeForm.member_access(MemberAccessAst { object: target, member }));
            } else if self.spelling().equals("[") {
                guard let indices = self.parse_indices() else { return nil; }
                target = self.arena.add(NodeForm.subscript(SubscriptAst { object: target, indices }));
            } else { break; }
        }
        self.finish(target, start)
    }
    def parse_binding() -> NodeId? {
        let start = self.current().span;
        let is_mutable = self.take().equals("var");
        guard let pattern = self.parse_pattern() else { return nil; }
        var type_annotation: NodeId? = nil;
        if self.match_text(":") {
            guard let type_node = self.parse_type() else { return nil; }
            type_annotation = type_node;
        }
        var initializer: NodeId? = nil;
        if self.match_text("=") {
            guard let value = self.parse_expression() else { return nil; }
            initializer = value;
        }
        let statement = self.make(NodeForm.var_decl(VarDeclAst {
            pattern, type_annotation, initializer, is_mutable
        }), start);
        if !self.expect(";") { return nil; }
        statement
    }
    def parse_assignment() -> NodeId? {
        let start = self.current().span;
        guard let target = self.parse_lvalue() else { return nil; }
        let op = self.spelling();
        if !is_assignment_operator(op) { self.fail("assignment operator"); return nil; }
        self.take();
        guard let value = self.parse_expression() else { return nil; }
        let statement = self.make(NodeForm.assignment(AssignmentAst { target, op, value }), start);
        if !self.expect(";") { return nil; }
        statement
    }
    def parse_return() -> NodeId? {
        let start = self.current().span;
        self.take();
        var value: NodeId? = nil;
        if !self.spelling().equals(";") {
            guard let expression = self.parse_expression() else { return nil; }
            value = expression;
        }
        if !self.expect(";") { return nil; }
        self.make(NodeForm.return_stmt(ReturnStmtAst { value, implicit: false }), start)
    }
    def parse_braced_body() -> Vec<NodeId>? {
        let statements = Vec<NodeId>.new();
        while !self.spelling().equals("}") {
            switch self.current().kind {
                case .eof: self.fail("'}'"); return nil;
                default: {}
            }
            let word = self.spelling();
            if word.equals("let") || word.equals("var") || word.equals("return") ||
               word.equals("break") || word.equals("continue") || word.equals("if") ||
               word.equals("guard") || word.equals("while") || word.equals("for") ||
               (word.equals("switch") && braced_switch_ahead(self.tokens, self.index)) || word.equals("defer") || word.equals("unsafe") ||
               word.equals("{") ||
               self.assignment_ahead() {
                guard let statement = self.parse_statement() else { return nil; }
                statements.push(statement);
                continue;
            }
            let expression_start = self.current().span;
            guard let expression = self.parse_expression() else { return nil; }
            if self.spelling().equals("}") {
                statements.push(self.arena.add(NodeForm.return_stmt(ReturnStmtAst {
                    value: expression, implicit: true
                })));
                break;
            }
            let statement = self.make(NodeForm.expr_stmt(ExprStmtAst { expr: expression }),
                                      expression_start);
            if !self.expect(";") { return nil; }
            statements.push(statement);
        }
        statements
    }
    def parse_block() -> NodeId? {
        let start = self.current().span;
        if !self.expect("{") { return nil; }
        guard let statements = self.parse_braced_body() else { return nil; }
        if !self.expect("}") { return nil; }
        self.make(NodeForm.block(BlockAst { statements, is_unsafe: false }), start)
    }
    def parse_arrow_lambda() -> NodeId? {
        let start = self.current().span;
        if !self.expect("(") { return nil; }
        let params = Vec<(NodeId, NodeId?)>.new();
        if !self.spelling().equals(")") {
            while true {
                guard let pattern = self.parse_pattern() else { return nil; }
                var annotation: NodeId? = nil;
                if self.match_text(":") {
                    guard let type_node = self.parse_type() else { return nil; }
                    annotation = type_node;
                }
                params.push((pattern, annotation));
                if !self.match_text(",") { break; }
            }
        }
        if !self.expect(")") { return nil; }
        if !self.expect("->") { return nil; }
        var return_type: NodeId? = nil;
        if !self.spelling().equals("{") {
            guard let declared = self.parse_type() else { return nil; }
            return_type = declared;
        }
        if !self.expect("{") { return nil; }
        guard let body = self.parse_braced_body() else { return nil; }
        if !self.expect("}") { return nil; }
        promote_tail_switch(self.arena, body);
        self.make(NodeForm.lambda(LambdaAst { params, body, return_type }), start)
    }
    def parse_if() -> NodeId? {
        let start = self.current().span;
        self.take();
        guard let condition = self.parse_condition("{") else { return nil; }
        guard let then_block = self.parse_block() else { return nil; }
        var else_block: NodeId? = nil;
        if self.match_text("else") {
            if self.spelling().equals("if") {
                guard let nested = self.parse_if() else { return nil; }
                else_block = nested;
            } else {
                guard let block = self.parse_block() else { return nil; }
                else_block = block;
            }
        }
        self.make(NodeForm.if_stmt(IfStmtAst { condition, then_block, else_block }), start)
    }
    def parse_guard() -> NodeId? {
        let start = self.current().span;
        self.take();
        guard let condition = self.parse_condition("else") else { return nil; }
        if !self.expect("else") { return nil; }
        guard let else_block = self.parse_block() else { return nil; }
        self.make(NodeForm.guard_stmt(GuardStmtAst { condition, else_block }), start)
    }
    def parse_while() -> NodeId? {
        let start = self.current().span;
        self.take();
        if self.spelling().equals("let") {
            // `while let p = e { body }` is `while true { if let p = e { body } else { break; } }`,
            // so continue re-evaluates e and break leaves the loop.
            guard let binding = self.parse_condition("{") else { return nil; }
            guard let body = self.parse_block() else { return nil; }
            let exit = Vec<NodeId>.new(); exit.push(self.make(NodeForm.break_stmt, start));
            let otherwise = self.make(NodeForm.block(BlockAst { statements: exit, is_unsafe: false }), start);
            let step = Vec<NodeId>.new();
            step.push(self.make(NodeForm.if_stmt(IfStmtAst { condition: binding, then_block: body, else_block: otherwise }), start));
            let loop_body = self.make(NodeForm.block(BlockAst { statements: step, is_unsafe: false }), start);
            let always = self.make(NodeForm.literal(LiteralAst { value: LiteralValue.boolean(true), kind: "bool" }), start);
            return self.make(NodeForm.while_stmt(WhileStmtAst { condition: always, body: loop_body }), start);
        }
        guard let condition = self.parse_condition_expression("{") else { return nil; }
        guard let body = self.parse_block() else { return nil; }
        self.make(NodeForm.while_stmt(WhileStmtAst { condition, body }), start)
    }
    def parse_for() -> NodeId? {
        let start = self.current().span;
        self.take();
        guard let pattern = self.parse_pattern() else { return nil; }
        if !self.expect("in") { return nil; }
        guard let iterable = self.parse_condition_expression("{") else { return nil; }
        guard let body = self.parse_block() else { return nil; }
        self.make(NodeForm.for_stmt(ForStmtAst { pattern, iterable, body }), start)
    }
    def parse_switch_case() -> NodeId? {
        let start = self.current().span;
        let is_default = self.match_text("default");
        let patterns = Vec<(NodeId, NodeId?)>.new();
        if !is_default {
            if !self.expect("case") { return nil; }
            while true {
                guard let pattern = self.parse_pattern() else { return nil; }
                var condition: NodeId? = nil;
                if self.match_text("where") {
                    guard let expression = self.parse_expression() else { return nil; }
                    condition = expression;
                }
                patterns.push((pattern, condition));
                if !self.match_text(",") { break; }
            }
        }
        if !self.expect(":") { return nil; }
        let body = Vec<NodeId>.new();
        while !self.spelling().equals("case") && !self.spelling().equals("default") &&
              !self.spelling().equals("}") {
            switch self.current().kind {
                case .eof: self.fail("'}'"); return nil;
                default: {}
            }
            guard let statement = self.parse_statement() else { return nil; }
            body.push(statement);
        }
        self.make(NodeForm.switch_case(SwitchCaseAst { patterns, body, is_default }), start)
    }
    def parse_switch() -> NodeId? {
        let start = self.current().span;
        self.take();
        guard let value = self.parse_condition_expression("{") else { return nil; }
        if !self.expect("{") { return nil; }
        let cases = Vec<NodeId>.new();
        while !self.spelling().equals("}") {
            switch self.current().kind {
                case .eof: self.fail("'}'"); return nil;
                default: {}
            }
            if !self.spelling().equals("case") && !self.spelling().equals("default") {
                self.fail("'case' or 'default'");
                return nil;
            }
            guard let branch = self.parse_switch_case() else { return nil; }
            cases.push(branch);
        }
        if !self.expect("}") { return nil; }
        self.make(NodeForm.switch_stmt(SwitchStmtAst { value, cases }), start)
    }
    def parse_defer() -> NodeId? {
        let start = self.current().span;
        self.take();
        guard let body = self.parse_block() else { return nil; }
        self.make(NodeForm.defer_stmt(DeferStmtAst { body }), start)
    }
    def parse_unsafe() -> NodeId? {
        self.take();
        guard let block = self.parse_block() else { return nil; }
        if let node = self.arena.get(block) {
            switch node.form {
                case .block(let data):
                    self.arena.replace(block, NodeForm.block(BlockAst {
                        statements: data.statements, is_unsafe: true
                    }));
                default: {}
            }
        }
        block
    }
    def parse_statement() -> NodeId? {
        let word = self.spelling();
        if word.equals("{") { return self.parse_block(); }
        if word.equals("if") { return self.parse_if(); }
        if word.equals("guard") { return self.parse_guard(); }
        if word.equals("while") { return self.parse_while(); }
        if word.equals("for") { return self.parse_for(); }
        if word.equals("switch") && braced_switch_ahead(self.tokens, self.index) { return self.parse_switch(); }
        if word.equals("defer") { return self.parse_defer(); }
        if word.equals("unsafe") { return self.parse_unsafe(); }
        if word.equals("let") || word.equals("var") { return self.parse_binding(); }
        if word.equals("return") { return self.parse_return(); }
        if word.equals("break") || word.equals("continue") {
            let start = self.current().span;
            self.take();
            self.match_text(";");
            if word.equals("break") { return self.make(NodeForm.break_stmt(), start); }
            return self.make(NodeForm.continue_stmt(), start);
        }
        if self.assignment_ahead() { return self.parse_assignment(); }
        let start = self.current().span;
        guard let expr = self.parse_expression() else { return nil; }
        let statement = self.make(NodeForm.expr_stmt(ExprStmtAst { expr }), start);
        if !self.expect(";") { return nil; }
        statement
    }
}

pub def parse_statement_prefix(tokens: Vec<LexToken>, arena: AstArena,
                               start_index: i32 = 0) -> StatementParseResult {
    let cursor = StatementCursor {
        tokens, arena, index: start_index, end_line: 0, end_column: 0, error: nil
    };
    let statement = cursor.parse_statement();
    StatementParseResult { statement, next_index: cursor.index, error: cursor.error }
}

pub def parse_statement_text(source: String, arena: AstArena) -> StatementParseResult {
    let lexed = tokenize(source);
    if let problem = lexed.error {
        return StatementParseResult { statement: nil, next_index: 0, error: problem.message };
    }
    let result = parse_statement_prefix(lexed.tokens, arena);
    if let problem = result.error { return result; }
    if result.next_index < lexed.tokens.len() - 1 {
        return StatementParseResult { statement: nil, next_index: result.next_index,
                                      error: "unexpected token after statement" };
    }
    result
}
