// File-level declarations share the recursive statement/expression core for
// function bodies and parameter defaults.
pub import "statement_parser.rl"
import std.collections
import "derive.rl"

pub struct DeclarationParseResult {
    pub let declaration: NodeId?;
    pub let next_index: i32;
    pub let remaining: String;
    pub let error: SyntaxError?;
    // Declarations synthesized alongside `declaration`, such as the extension for `struct S: P`.
    pub let extra: Vec<NodeId>;
}

struct DeclarationCursor {
    let tokens: Vec<LexToken>;
    let arena: AstArena;
    var index: i32;
    var fragment: String;
    var fragment_offset: i32;
    var end_line: i32;
    var end_column: i32;
    var error: SyntaxError?;
    let extra: Vec<NodeId>;
    // Source text of field types and defaults, by node, for derived conformances.
    let texts: Dict<i32, String>;

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
        self.error = expected_token(expected, self.spelling(), self.tokens, self.index, Span.new(token.span.line, token.span.column + self.fragment_offset, token.span.end_line, token.span.end_column));
    }
    def expect(wanted: String) -> Bool {
        if self.match_text(wanted) { return true; }
        self.fail(f"'{wanted}'");
        false
    }
    def make(form: NodeForm, start: Span) -> NodeId {
        self.arena.add(form, Span.new(start.line, start.column, self.end_line, self.end_column))
    }
    def visibility() -> String {
        let word = self.spelling();
        if word.equals("pub") || word.equals("private") || word.equals("internal") {
            return self.take();
        }
        "internal"
    }
    def parse_type() -> NodeId? {
        if self.fragment.len() > 0 { self.fail("type"); return nil; }
        self.accept_type_result(parse_type_prefix(self.tokens, self.arena, self.index))
    }
    // The source text of tokens from `start` to the cursor, without a split token's unread part.
    def text_from(start: i32) -> String {
        var text = "";
        var index = start;
        while index < self.index {
            if index > start { text += " "; }
            text += self.tokens[index].text;
            index += 1;
        }
        if self.fragment.len() > 0 && self.index < self.tokens.len() {
            let token = self.tokens[self.index].text;
            if index > start { text += " "; }
            text += token.substring(0, (token.len() as i32) - (self.fragment.len() as i32));
        }
        text
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
    def parse_named_bound() -> NodeId? {
        if self.fragment.len() > 0 { self.fail("type name"); return nil; }
        self.accept_type_result(parse_named_type_prefix(self.tokens, self.arena, self.index))
    }
    def parse_expression() -> NodeId? {
        if self.fragment.len() > 0 { self.fail("expression"); return nil; }
        let result = parse_expression_prefix(self.tokens, self.arena, self.index);
        if let problem = result.error { self.error = problem; return nil; }
        if result.remaining.len() > 0 { self.fail("complete expression"); return nil; }
        self.index = result.next_index;
        if self.index > 0 {
            let span = self.tokens[self.index - 1].span;
            self.end_line = span.end_line;
            self.end_column = span.end_column;
        }
        result.expression
    }
    def parse_block() -> NodeId? {
        if self.fragment.len() > 0 { self.fail("block"); return nil; }
        let result = parse_statement_prefix(self.tokens, self.arena, self.index);
        if let problem = result.error { self.error = problem; return nil; }
        guard let id = result.statement else { self.fail("block"); return nil; }
        guard let node = self.arena.get(id) else { self.fail("block"); return nil; }
        switch node.form {
            case .block(_): {}
            default: self.fail("block"); return nil;
        }
        self.index = result.next_index;
        let span = self.tokens[self.index - 1].span;
        self.end_line = span.end_line;
        self.end_column = span.end_column;
        id
    }
    def parse_generic_param() -> NodeId? {
        if !self.at_identifier() { self.fail("generic parameter name"); return nil; }
        let start = self.current().span;
        let name = self.take();
        var bounds: Vec<NodeId>? = nil;
        if self.match_text(":") {
            let found = Vec<NodeId>.new();
            guard let first = self.parse_named_bound() else { return nil; }
            found.push(first);
            while self.match_text("&") {
                guard let next = self.parse_named_bound() else { return nil; }
                found.push(next);
            }
            bounds = found;
        }
        self.make(NodeForm.generic_param(GenericParamAst { name, bounds }), start)
    }
    def parse_generic_params() -> Vec<NodeId>? {
        let params = Vec<NodeId>.new();
        if !self.match_text("<") { return params; }
        guard let first = self.parse_generic_param() else { return nil; }
        params.push(first);
        while self.match_text(",") {
            guard let next = self.parse_generic_param() else { return nil; }
            params.push(next);
        }
        if !self.expect(">") { return nil; }
        params
    }
    def parse_constraint() -> NodeId? {
        let start = self.current().span;
        guard let subject = self.parse_named_bound() else { return nil; }
        let bounds = Vec<NodeId>.new();
        var equal_type: NodeId? = nil;
        var kind = "conforms";
        if self.match_text(":") {
            guard let first = self.parse_named_bound() else { return nil; }
            bounds.push(first);
            while self.match_text("&") {
                guard let next = self.parse_named_bound() else { return nil; }
                bounds.push(next);
            }
        } else if self.match_text("==") {
            kind = "equals";
            guard let target = self.parse_type() else { return nil; }
            equal_type = target;
        } else { self.fail("constraint operator"); return nil; }
        self.make(NodeForm.constraint(ConstraintAst {
            subject: AstConstraintSubject.type_ref(subject), kind, bounds, equal_type
        }), start)
    }
    // `: P, Q` after a struct, enum or protocol name.
    def parse_inheritance() -> Vec<NodeId>? {
        let bounds = Vec<NodeId>.new();
        if !self.match_text(":") { return bounds; }
        guard let first = self.parse_named_bound() else { return nil; }
        bounds.push(first);
        while self.match_text(",") {
            guard let next = self.parse_named_bound() else { return nil; }
            bounds.push(next);
        }
        bounds
    }
    // `struct S<T>: P, Q` declares its conformances through `extension<T> S<T>: P, Q {}`.
    // Generates the methods of derivable conformances (see derive.rl) as an
    // extension declaration located at the type's declaration.
    def derive(name: String, generic_params: Vec<NodeId>, conformances: Vec<NodeId>, members: Vec<NodeId>, is_enum: Bool, start: Span) -> Void {
        let protocols = Vec<String>.new();
        for id in conformances { if let node = self.arena.get(id) { switch node.form {
            case .named_type(let named): if derivable_protocol(named.name) { protocols.push(named.name); }
            default: {}
        } } }
        if protocols.len() == 0 { return; }
        let generic_names = Vec<String>.new();
        for id in generic_params { if let node = self.arena.get(id) { switch node.form { case .generic_param(let param): generic_names.push(param.name); default: {} } } }
        let defined = Vec<String>.new(); let fields = Vec<DeriveField>.new(); let cases = Vec<DeriveCase>.new();
        let field_spans = Vec<Span>.new(); let case_spans = Vec<Span>.new();
        for id in members { if let node = self.arena.get(id) { switch node.form {
            case .func_decl(let func): defined.push(func.name);
            case .property_decl(let property):
                if property.accessors != nil { continue; }
                guard let annotation = property.type_annotation else { continue; }
                var fallback: String? = nil;
                if let value = property.initializer { fallback = self.texts[value.id]; }
                fields.push(DeriveField { name: property.name, type_text: self.texts[annotation.id] ?? "", default_text: fallback });
                field_spans.push(node.span ?? start);
            case .enum_case_decl(let declaration):
                for case_id in declaration.cases { if let case_node = self.arena.get(case_id) { switch case_node.form {
                    case .enum_case_def(let definition):
                        let labels = Vec<String?>.new(); let types = Vec<String>.new();
                        for pair in definition.payload { labels.push(pair.0); types.push(self.texts[pair.1.id] ?? ""); }
                        cases.push(DeriveCase { name: definition.name, labels, types });
                        case_spans.push(case_node.span ?? node.span ?? start);
                    default: {}
                } } }
            default: {}
        } } }
        let source = derive_source(DeriveRequest { name, generic_names, protocols, defined, fields, cases, is_enum });
        if source.len() == 0 { return; }
        let lexed = tokenize(source);
        if let problem = lexed.error { self.error = SyntaxError { message: f"cannot derive {protocols[0]} for {name}: {problem.message}", span: start }; return; }
        let first = self.arena.len();
        let result = parse_declaration_prefix(lexed.tokens, self.arena, 0);
        if let problem = result.error { self.error = SyntaxError { message: f"cannot derive {protocols[0]} for {name}: {problem.message}", span: start }; return; }
        // Errors in derived code point at the field or enum case a generated line handles, else at the type.
        // Case handling spans the lines nested under the line that names the case.
        let line_spans = Vec<Span>.new();
        var current: Span? = nil;
        for line in source.split("\n") {
            var marked = false;
            for index in 0..<cases.len() {
                let name = cases[index].name;
                if line.contains(f"case .{name}(") || line.contains(f"case .{name}:") || line.contains(f"equals(\"{name}\")") { current = case_spans[index]; marked = true; }
            }
            if !marked && !line.starts_with("            ") { current = nil; }
            var span = current ?? start;
            for index in 0..<fields.len() {
                let name = fields[index].name;
                if line.contains(f"self.{name} ") || line.contains(f"self.{name}.") || line.contains(f"\"{name}\"") || line.contains(f"decoded{index}:") {
                    span = field_spans[index];
                }
            }
            line_spans.push(span);
        }
        for index in first..<self.arena.len() { if let node = self.arena.get(NodeId { id: index }) {
            var span = start;
            if let generated = node.span { if generated.line >= 1 && generated.line <= line_spans.len() { span = line_spans[generated.line - 1]; } }
            node.span = span;
        } }
        if let declaration = result.declaration { self.extra.push(declaration); }
        for extra in result.extra { self.extra.push(extra); }
    }
    def conformance_extension(visibility: String, name: String, generic_params: Vec<NodeId>, declared: Vec<NodeId>, start: Span) -> Void {
        // Derivable protocols are declared by the derived extension instead.
        let conformances = Vec<NodeId>.new();
        for id in declared {
            var derivable = false;
            if let node = self.arena.get(id) { switch node.form { case .named_type(let named): derivable = derivable_protocol(named.name); default: {} } }
            if !derivable { conformances.push(id); }
        }
        if conformances.len() == 0 { return; }
        let params = Vec<NodeId>.new(); let args = Vec<NodeId>.new();
        for id in generic_params { if let node = self.arena.get(id) { switch node.form {
            case .generic_param(let param):
                params.push(self.make(NodeForm.generic_param(GenericParamAst { name: param.name, bounds: param.bounds }), start));
                args.push(self.make(NodeForm.named_type(NamedTypeAst { name: param.name, module_path: Vec<String>.new(), generic_args: Vec<NodeId>.new() }), start));
            default: {}
        } } }
        let extended = self.make(NodeForm.named_type(NamedTypeAst { name, module_path: Vec<String>.new(), generic_args: args }), start);
        self.extra.push(self.make(NodeForm.extension_decl(ExtensionDeclAst {
            visibility, generic_params: params, extended_type: extended, conformances,
            constraints: Vec<NodeId>.new(), members: Vec<NodeId>.new()
        }), start));
    }
    def parse_constraints() -> Vec<NodeId>? {
        let constraints = Vec<NodeId>.new();
        if !self.match_text("where") { return constraints; }
        guard let first = self.parse_constraint() else { return nil; }
        constraints.push(first);
        while self.match_text(",") {
            guard let next = self.parse_constraint() else { return nil; }
            constraints.push(next);
        }
        constraints
    }
    def parse_param() -> NodeId? {
        if !self.at_identifier() { self.fail("parameter name"); return nil; }
        let start = self.current().span;
        let first = self.take();
        var external_name: String? = nil;
        var internal_name = first;
        if self.at_identifier() && !self.spelling().equals(":") {
            if !first.equals("_") { external_name = first; }
            internal_name = self.take();
        }
        if !self.expect(":") { return nil; }
        guard let type_annotation = self.parse_type() else { return nil; }
        var default_value: NodeId? = nil;
        if self.match_text("=") {
            guard let value = self.parse_expression() else { return nil; }
            default_value = value;
        }
        self.make(NodeForm.param(ParamAst {
            external_name, internal_name, type_annotation, default_value
        }), start)
    }
    def parse_params() -> Vec<NodeId>? {
        if !self.expect("(") { return nil; }
        let params = Vec<NodeId>.new();
        if self.match_text(")") { return params; }
        guard let first = self.parse_param() else { return nil; }
        params.push(first);
        while self.match_text(",") {
            guard let next = self.parse_param() else { return nil; }
            params.push(next);
        }
        if !self.expect(")") { return nil; }
        params
    }
    def parse_import() -> NodeId? {
        let start = self.current().span;
        let visibility = self.visibility();
        if !self.expect("import") { return nil; }
        let module = Vec<String>.new();
        var path = "";
        let token = self.current();
        switch token.kind {
            case .string:
                let raw = self.take();
                path = raw.substring(1, (raw.len() as i32) - 2);
            case .identifier:
                module.push(self.take());
                while self.match_text(".") {
                    if !self.at_identifier() { self.fail("module name"); return nil; }
                    module.push(self.take());
                }
                path = join_strings(module, "/") + ".rl";
            default: self.fail("import path"); return nil;
        }
        var alias: String? = nil;
        if self.match_text("as") {
            if !self.at_identifier() { self.fail("import alias"); return nil; }
            alias = self.take();
        }
        self.match_text(";");
        self.make(NodeForm.import_decl(ImportDeclAst { visibility, path, module, alias }), start)
    }
    def parse_type_alias() -> NodeId? {
        let start = self.current().span;
        let visibility = self.visibility();
        if !self.expect("typealias") { return nil; }
        if !self.at_identifier() { self.fail("type alias name"); return nil; }
        let name = self.take();
        guard let generic_params = self.parse_generic_params() else { return nil; }
        if !self.expect("=") { return nil; }
        guard let aliased_type = self.parse_type() else { return nil; }
        if !self.expect(";") { return nil; }
        self.make(NodeForm.type_alias_decl(TypeAliasDeclAst {
            visibility, name, aliased_type, generic_params
        }), start)
    }
    def parse_func() -> NodeId? {
        let start = self.current().span;
        let visibility = self.visibility();
        let is_unsafe = self.match_text("unsafe");
        let is_static = self.match_text("static");
        if !self.expect("def") { return nil; }
        if !self.at_identifier() { self.fail("function name"); return nil; }
        let name = self.take();
        guard let generic_params = self.parse_generic_params() else { return nil; }
        guard let params = self.parse_params() else { return nil; }
        let is_async = self.match_text("async");
        var return_type: NodeId? = nil;
        if self.match_text("->") {
            guard let result = self.parse_type() else { return nil; }
            return_type = result;
        }
        guard let constraints = self.parse_constraints() else { return nil; }
        guard let body = self.parse_block() else { return nil; }
        var value_returning = false;
        if let result = return_type {
            value_returning = true;
            if let node = self.arena.get(result) {
                switch node.form {
                    case .builtin_type(let data):
                        if data.name.equals("Void") { value_returning = false; }
                    default: {}
                }
            }
        }
        if value_returning {
            if let node = self.arena.get(body) {
                switch node.form {
                    case .block(let data): promote_tail_switch(self.arena, data.statements);
                    default: {}
                }
            }
        }
        self.make(NodeForm.func_decl(FuncDeclAst {
            visibility, name, generic_params, params, return_type, constraints, body,
            is_async, is_static, is_unsafe
        }), start)
    }
    def parse_extern_func() -> NodeId? {
        let start = self.current().span;
        let visibility = self.visibility();
        if !self.expect("extern") { return nil; }
        let token = self.current();
        var abi = "";
        switch token.kind {
            case .string:
                let raw = self.take();
                abi = raw.substring(1, (raw.len() as i32) - 2);
            default: self.fail("ABI string"); return nil;
        }
        if !self.expect("def") { return nil; }
        if !self.at_identifier() { self.fail("extern function name"); return nil; }
        let name = self.take();
        guard let generic_params = self.parse_generic_params() else { return nil; }
        guard let params = self.parse_params() else { return nil; }
        // An `async` mark is accepted without setting the declaration flag.
        self.match_text("async");
        var return_type: NodeId? = nil;
        if self.match_text("->") {
            guard let result = self.parse_type() else { return nil; }
            return_type = result;
        }
        guard let constraints = self.parse_constraints() else { return nil; }
        if !self.expect(";") { return nil; }
        self.make(NodeForm.extern_func_decl(ExternFuncDeclAst {
            visibility, abi, name, generic_params, params, return_type, constraints,
            is_async: false
        }), start)
    }
    def parse_property() -> NodeId? {
        let start = self.current().span;
        let visibility = self.visibility();
        let is_mutable = self.match_text("var");
        if !is_mutable && !self.expect("let") { return nil; }
        if !self.at_identifier() { self.fail("property name"); return nil; }
        let name = self.take();
        if !self.expect(":") { return nil; }
        let type_start = self.index;
        guard let type_annotation = self.parse_type() else { return nil; }
        self.texts[type_annotation.id] = self.text_from(type_start);
        var initializer: NodeId? = nil;
        if self.match_text("=") {
            let value_start = self.index;
            guard let value = self.parse_expression() else { return nil; }
            self.texts[value.id] = self.text_from(value_start);
            initializer = value;
        }
        self.match_text(";");
        self.make(NodeForm.property_decl(PropertyDeclAst {
            visibility, name, type_annotation, initializer, is_mutable, accessors: nil
        }), start)
    }
    def parse_struct() -> NodeId? {
        let start = self.current().span;
        let visibility = self.visibility();
        if !self.expect("struct") { return nil; }
        if !self.at_identifier() { self.fail("struct name"); return nil; }
        let name = self.take();
        guard let generic_params = self.parse_generic_params() else { return nil; }
        guard let conformances = self.parse_inheritance() else { return nil; }
        guard let constraints = self.parse_constraints() else { return nil; }
        if !self.expect("{") { return nil; }
        let members = Vec<NodeId>.new();
        while !self.spelling().equals("}") {
            switch self.current().kind {
                case .eof: self.fail("'}'"); return nil;
                default: {}
            }
            let word = self.spelling();
            let next = self.next_spelling();
            if word.equals("let") || word.equals("var") ||
               next.equals("let") || next.equals("var") {
                guard let member = self.parse_property() else { return nil; }
                members.push(member);
            } else if word.equals("def") || word.equals("unsafe") || word.equals("static") ||
                      next.equals("def") || next.equals("unsafe") || next.equals("static") {
                guard let member = self.parse_func() else { return nil; }
                members.push(member);
            } else {
                self.fail("struct member");
                return nil;
            }
        }
        if !self.expect("}") { return nil; }
        let declaration = self.make(NodeForm.struct_decl(StructDeclAst {
            visibility, name, generic_params, constraints, members
        }), start);
        self.conformance_extension(visibility, name, generic_params, conformances, start);
        self.derive(name, generic_params, conformances, members, false, start);
        declaration
    }
    def parse_enum_case_def() -> NodeId? {
        if !self.at_identifier() { self.fail("enum case name"); return nil; }
        let start = self.current().span;
        let name = self.take();
        let payload = Vec<(String?, NodeId)>.new();
        if self.match_text("(") {
            if !self.spelling().equals(")") {
                while true {
                    var label: String? = nil;
                    if self.at_identifier() && self.next_spelling().equals(":") {
                        label = self.take();
                        self.take();
                    }
                    let type_start = self.index;
                    guard let type_node = self.parse_type() else { return nil; }
                    self.texts[type_node.id] = self.text_from(type_start);
                    payload.push((label, type_node));
                    if !self.match_text(",") { break; }
                }
            }
            if !self.expect(")") { return nil; }
        }
        self.make(NodeForm.enum_case_def(EnumCaseDefAst { name, payload }), start)
    }
    def parse_enum_case_decl() -> NodeId? {
        let start = self.current().span;
        if !self.expect("case") { return nil; }
        let cases = Vec<NodeId>.new();
        guard let first = self.parse_enum_case_def() else { return nil; }
        cases.push(first);
        while self.match_text(",") {
            guard let next = self.parse_enum_case_def() else { return nil; }
            cases.push(next);
        }
        self.match_text(";");
        self.make(NodeForm.enum_case_decl(EnumCaseDeclAst {
            visibility: "internal", cases
        }), start)
    }
    def parse_enum() -> NodeId? {
        let start = self.current().span;
        let visibility = self.visibility();
        if !self.expect("enum") { return nil; }
        if !self.at_identifier() { self.fail("enum name"); return nil; }
        let name = self.take();
        guard let generic_params = self.parse_generic_params() else { return nil; }
        guard let conformances = self.parse_inheritance() else { return nil; }
        guard let constraints = self.parse_constraints() else { return nil; }
        if !self.expect("{") { return nil; }
        let members = Vec<NodeId>.new();
        while !self.spelling().equals("}") {
            switch self.current().kind {
                case .eof: self.fail("'}'"); return nil;
                default: {}
            }
            let word = self.spelling();
            let next = self.next_spelling();
            if word.equals("case") {
                guard let member = self.parse_enum_case_decl() else { return nil; }
                members.push(member);
            } else if word.equals("def") || word.equals("unsafe") || word.equals("static") ||
                      next.equals("def") || next.equals("unsafe") || next.equals("static") {
                guard let member = self.parse_func() else { return nil; }
                members.push(member);
            } else {
                self.fail("enum member");
                return nil;
            }
        }
        if !self.expect("}") { return nil; }
        let declaration = self.make(NodeForm.enum_decl(EnumDeclAst {
            visibility, name, generic_params, constraints, members
        }), start);
        self.conformance_extension(visibility, name, generic_params, conformances, start);
        self.derive(name, generic_params, conformances, members, true, start);
        declaration
    }
    def parse_protocol_func() -> NodeId? {
        let start = self.current().span;
        let is_static = self.match_text("static");
        if !self.expect("def") { return nil; }
        if !self.at_identifier() { self.fail("requirement name"); return nil; }
        let name = self.take();
        guard let generic_params = self.parse_generic_params() else { return nil; }
        guard let params = self.parse_params() else { return nil; }
        let is_async = self.match_text("async");
        var return_type: NodeId? = nil;
        if self.match_text("->") {
            guard let result = self.parse_type() else { return nil; }
            return_type = result;
        }
        if !self.expect(";") { return nil; }
        self.make(NodeForm.protocol_func_req(ProtocolFuncReqAst {
            visibility: "internal", name, generic_params, params, return_type,
            is_async, is_static
        }), start)
    }
    def parse_protocol_property() -> NodeId? {
        let start = self.current().span;
        let is_var = self.match_text("var");
        if !is_var && !self.expect("let") { return nil; }
        if !self.at_identifier() { self.fail("requirement name"); return nil; }
        let name = self.take();
        if !self.expect(":") { return nil; }
        guard let type_annotation = self.parse_type() else { return nil; }
        if !self.expect("{") { return nil; }
        var has_getter = false;
        var has_setter = false;
        var count = 0;
        while self.spelling().equals("get") || self.spelling().equals("set") {
            if self.match_text("get") { has_getter = true; }
            else { self.take(); has_setter = true; }
            count += 1;
        }
        if count == 0 { self.fail("accessor kind"); return nil; }
        if !self.expect("}") || !self.expect(";") { return nil; }
        self.make(NodeForm.protocol_prop_req(ProtocolPropReqAst {
            visibility: "internal", name, type_annotation,
            is_mutable: is_var || has_setter, has_getter, has_setter
        }), start)
    }
    def parse_associated_type() -> NodeId? {
        let start = self.current().span;
        if !self.expect("associatedtype") { return nil; }
        if !self.at_identifier() { self.fail("associated type name"); return nil; }
        let name = self.take();
        guard let constraints = self.parse_constraints() else { return nil; }
        if !self.expect(";") { return nil; }
        self.make(NodeForm.associated_type_decl(AssociatedTypeDeclAst {
            visibility: "internal", name, constraints
        }), start)
    }
    def parse_protocol() -> NodeId? {
        let start = self.current().span;
        let visibility = self.visibility();
        if !self.expect("protocol") { return nil; }
        if !self.at_identifier() { self.fail("protocol name"); return nil; }
        let name = self.take();
        guard let generic_params = self.parse_generic_params() else { return nil; }
        guard let parents = self.parse_inheritance() else { return nil; }
        guard let constraints = self.parse_constraints() else { return nil; }
        // `protocol B: A, C` is stored as the constraint `Self: A & C`.
        if parents.len() > 0 {
            let subject = self.make(NodeForm.named_type(NamedTypeAst { name: "Self", module_path: Vec<String>.new(), generic_args: Vec<NodeId>.new() }), start);
            constraints.push(self.make(NodeForm.constraint(ConstraintAst { subject: AstConstraintSubject.type_ref(subject), kind: "conforms", bounds: parents, equal_type: nil }), start));
        }
        if !self.expect("{") { return nil; }
        let members = Vec<NodeId>.new();
        while !self.spelling().equals("}") {
            switch self.current().kind {
                case .eof: self.fail("'}'"); return nil;
                default: {}
            }
            let word = self.spelling();
            var member: NodeId? = nil;
            if word.equals("def") || (word.equals("static") && self.next_spelling().equals("def")) { member = self.parse_protocol_func(); }
            else if word.equals("let") || word.equals("var") {
                member = self.parse_protocol_property();
            } else if word.equals("associatedtype") {
                member = self.parse_associated_type();
            } else { self.fail("protocol member"); return nil; }
            guard let id = member else { return nil; }
            members.push(id);
        }
        if !self.expect("}") { return nil; }
        self.make(NodeForm.protocol_decl(ProtocolDeclAst {
            visibility, name, generic_params, constraints, members
        }), start)
    }
    def parse_extension() -> NodeId? {
        let start = self.current().span;
        let visibility = self.visibility();
        if !self.expect("extension") { return nil; }
        guard let generic_params = self.parse_generic_params() else { return nil; }
        guard let extended_type = self.parse_named_bound() else { return nil; }
        // `extension<T> T?` extends optionals.
        var target = extended_type;
        if self.spelling().equals("?") {
            let span = self.current().span; self.index += 1;
            target = self.make(NodeForm.optional_type(OptionalTypeAst { inner: extended_type }), span);
        }
        let conformances = Vec<NodeId>.new();
        if self.match_text(":") {
            guard let first = self.parse_named_bound() else { return nil; }
            conformances.push(first);
            while self.match_text(",") {
                guard let next = self.parse_named_bound() else { return nil; }
                conformances.push(next);
            }
        }
        guard let constraints = self.parse_constraints() else { return nil; }
        if !self.expect("{") { return nil; }
        let members = Vec<NodeId>.new();
        while !self.spelling().equals("}") {
            switch self.current().kind {
                case .eof: self.fail("'}'"); return nil;
                default: {}
            }
            let word = self.spelling();
            let next = self.next_spelling();
            if word.equals("let") || word.equals("var") ||
               next.equals("let") || next.equals("var") {
                guard let member = self.parse_property() else { return nil; }
                members.push(member);
            } else if word.equals("def") || word.equals("unsafe") || word.equals("static") ||
                      next.equals("def") || next.equals("unsafe") || next.equals("static") {
                guard let member = self.parse_func() else { return nil; }
                members.push(member);
            } else { self.fail("extension member"); return nil; }
        }
        if !self.expect("}") { return nil; }
        self.make(NodeForm.extension_decl(ExtensionDeclAst {
            visibility, generic_params, extended_type: target, conformances, constraints, members
        }), start)
    }
    def parse_constant() -> NodeId? {
        let start = self.current().span;
        let visibility = self.visibility();
        if !self.expect("let") { return nil; }
        if !self.at_identifier() { self.fail("constant name"); return nil; }
        let name = self.take();
        var type_annotation: NodeId? = nil;
        if self.match_text(":") {
            guard let annotation = self.parse_type() else { return nil; }
            type_annotation = annotation;
        }
        if !self.expect("=") { return nil; }
        guard let value = self.parse_expression() else { return nil; }
        if !self.expect(";") { return nil; }
        self.make(NodeForm.constant_decl(ConstantDeclAst { visibility, name, type_annotation, value }), start)
    }
    def parse_declaration() -> NodeId? {
        let word = self.spelling();
        let next = self.next_spelling();
        if word.equals("let") || next.equals("let") { return self.parse_constant(); }
        if word.equals("var") || next.equals("var") { self.fail("a declaration (module-level `var` is not supported; use `let` for a constant)"); return nil; }
        if word.equals("import") || next.equals("import") { return self.parse_import(); }
        if word.equals("typealias") || next.equals("typealias") { return self.parse_type_alias(); }
        if word.equals("extern") || next.equals("extern") { return self.parse_extern_func(); }
        if word.equals("struct") || next.equals("struct") { return self.parse_struct(); }
        if word.equals("enum") || next.equals("enum") { return self.parse_enum(); }
        if word.equals("protocol") || next.equals("protocol") { return self.parse_protocol(); }
        if word.equals("extension") || next.equals("extension") { return self.parse_extension(); }
        if word.equals("def") || word.equals("unsafe") || word.equals("static") ||
           next.equals("def") || next.equals("unsafe") || next.equals("static") {
            return self.parse_func();
        }
        self.fail("declaration");
        nil
    }
}

pub def parse_declaration_prefix(tokens: Vec<LexToken>, arena: AstArena,
                                 start_index: i32 = 0) -> DeclarationParseResult {
    let cursor = DeclarationCursor {
        tokens, arena, index: start_index, fragment: "", fragment_offset: 0,
        end_line: 0, end_column: 0, error: nil, extra: Vec<NodeId>.new(), texts: Dict<i32, String>.new()
    };
    let declaration = cursor.parse_declaration();
    DeclarationParseResult {
        declaration, next_index: cursor.index, remaining: cursor.fragment, error: cursor.error, extra: cursor.extra
    }
}
