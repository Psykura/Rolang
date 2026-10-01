// File-level declarations share the recursive statement/expression core for
// function bodies and parameter defaults.
pub import "statement_parser.rl"
import std.collections

pub struct DeclarationParseResult {
    pub let declaration: NodeId?;
    pub let next_index: i32;
    pub let remaining: String;
    pub let error: String?;
}

struct DeclarationCursor {
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
        let throws = self.match_text("throws");
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
            is_async, throws, is_static, is_unsafe
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
        // Extern marks are accepted without setting declaration flags.
        self.match_text("async");
        self.match_text("throws");
        var return_type: NodeId? = nil;
        if self.match_text("->") {
            guard let result = self.parse_type() else { return nil; }
            return_type = result;
        }
        guard let constraints = self.parse_constraints() else { return nil; }
        if !self.expect(";") { return nil; }
        self.make(NodeForm.extern_func_decl(ExternFuncDeclAst {
            visibility, abi, name, generic_params, params, return_type, constraints,
            is_async: false, throws: false
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
        guard let type_annotation = self.parse_type() else { return nil; }
        var initializer: NodeId? = nil;
        if self.match_text("=") {
            guard let value = self.parse_expression() else { return nil; }
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
        self.make(NodeForm.struct_decl(StructDeclAst {
            visibility, name, generic_params, constraints, members
        }), start)
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
                    guard let type_node = self.parse_type() else { return nil; }
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
        self.make(NodeForm.enum_decl(EnumDeclAst {
            visibility, name, generic_params, constraints, members
        }), start)
    }
    def parse_protocol_func() -> NodeId? {
        let start = self.current().span;
        if !self.expect("def") { return nil; }
        if !self.at_identifier() { self.fail("requirement name"); return nil; }
        let name = self.take();
        guard let generic_params = self.parse_generic_params() else { return nil; }
        guard let params = self.parse_params() else { return nil; }
        let is_async = self.match_text("async");
        let throws = self.match_text("throws");
        var return_type: NodeId? = nil;
        if self.match_text("->") {
            guard let result = self.parse_type() else { return nil; }
            return_type = result;
        }
        if !self.expect(";") { return nil; }
        self.make(NodeForm.protocol_func_req(ProtocolFuncReqAst {
            visibility: "internal", name, generic_params, params, return_type,
            is_async, throws
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
        guard let constraints = self.parse_constraints() else { return nil; }
        if !self.expect("{") { return nil; }
        let members = Vec<NodeId>.new();
        while !self.spelling().equals("}") {
            switch self.current().kind {
                case .eof: self.fail("'}'"); return nil;
                default: {}
            }
            let word = self.spelling();
            var member: NodeId? = nil;
            if word.equals("def") { member = self.parse_protocol_func(); }
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
            visibility, generic_params, extended_type, conformances, constraints, members
        }), start)
    }
    def parse_declaration() -> NodeId? {
        let word = self.spelling();
        let next = self.next_spelling();
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
        end_line: 0, end_column: 0, error: nil
    };
    let declaration = cursor.parse_declaration();
    DeclarationParseResult {
        declaration, next_index: cursor.index, remaining: cursor.fragment, error: cursor.error
    }
}

pub def parse_declaration_text(source: String, arena: AstArena) -> DeclarationParseResult {
    let lexed = tokenize(source);
    if let problem = lexed.error {
        return DeclarationParseResult { declaration: nil, next_index: 0,
                                        remaining: "", error: problem.message };
    }
    let result = parse_declaration_prefix(lexed.tokens, arena);
    if let problem = result.error { return result; }
    if result.remaining.len() > 0 || result.next_index < lexed.tokens.len() - 1 {
        return DeclarationParseResult {
            declaration: nil, next_index: result.next_index, remaining: result.remaining,
            error: "unexpected token after declaration"
        };
    }
    result
}
