// Coverage checking for enum, Optional and Bool switches.
pub import "ast.rl"
pub import "symbols.rl"
pub import "types.rl"
pub import "checker_core.rl"
import std.collections

enum PatternCoverage { case catch_all; case values(Vec<String>); }

def name_before(a: String, b: String) -> Bool {
    var index = 0;
    while index < a.len() && index < b.len() {
        let left = a.byte_at(index); let right = b.byte_at(index);
        if left != right { return left < right; }
        index += 1;
    }
    a.len() < b.len()
}

pub struct ExhaustivenessChecker {
    let arena: AstArena;
    let type_table: TypeTable;
    let symbol_table: SymbolTable;
    let report_error: (TypeErrorKind, String) -> Void;
    pub static def new(arena: AstArena, type_table: TypeTable, symbol_table: SymbolTable,
                       report_error: (TypeErrorKind, String) -> Void) -> ExhaustivenessChecker {
        ExhaustivenessChecker { arena, type_table, symbol_table, report_error }
    }
    pub def check_switch(id: NodeId, value_type: TypeId) -> Void {
        guard let node = self.arena.get(id) else { return; }
        let cases = Vec<NodeId>.new();
        switch node.form {
            case .switch_stmt(let data): for item in data.cases { cases.push(item); }
            case .switch_expr(let data): for item in data.cases { cases.push(item); }
            default: return;
        }
        for item in cases {
            if let branch = self.arena.get(item) {
                switch branch.form { case .switch_case(let data): if data.is_default { return; } default: {} }
            }
        }
        guard let info = self.type_table.get_type(value_type) else { return; }
        var expression = false;
        switch node.form { case .switch_expr: expression = true; default: {} }
        let all = Vec<String>.new();
        var domain = "";
        switch info.data {
            case .enum_type(let data):
                guard let symbol = self.symbol_table.get_symbol(data.symbol_id) else { return; }
                guard let declaration = symbol.decl_node else { return; }
                guard let decl = self.arena.get(declaration) else { return; }
                switch decl.form {
                    case .enum_decl(let enum_data):
                        for member in enum_data.members {
                            guard let member_node = self.arena.get(member) else { continue; }
                            switch member_node.form {
                                case .enum_case_decl(let group):
                                    for case_id in group.cases {
                                        if let case_node = self.arena.get(case_id) {
                                            switch case_node.form { case .enum_case_def(let item): all.push(item.name); default: {} }
                                        }
                                    }
                                default: {}
                            }
                        }
                    default: return;
                }
                domain = "enum";
            case .optional(_): domain = "optional"; all.push("some"); all.push("none");
            case .primitive(let primitive):
                switch primitive {
                    case .bool_type: domain = "bool"; all.push("true"); all.push("false");
                    default: self.require_catch_all(cases, expression, value_type); return;
                }
            default: self.require_catch_all(cases, expression, value_type); return;
        }
        let matched = Dict<String, Bool>.with_capacity(16, 1);
        for item in cases {
            guard let branch = self.arena.get(item) else { continue; }
            switch branch.form {
                case .switch_case(let data):
                    for pair in data.patterns {
                        if let guard_expr = pair.1 { continue; }
                        switch self.coverage(pair.0, domain) {
                            case .catch_all: return;
                            case .values(let names): for name in names { matched[name] = true; }
                        }
                    }
                default: {}
            }
        }
        let missing = Vec<String>.new();
        let seen = Dict<String, Bool>.with_capacity(16, 1);
        for name in all {
            if !matched.contains(name) && !seen.contains(name) {
                seen[name] = true;
                if domain.equals("optional") {
                    missing.push(optional_case_display(name));
                } else { missing.push(name); }
            }
        }
        if missing.len() == 0 { return; }
        if domain.equals("enum") {
            for index in 1..<missing.len() {
                var position = index;
                while position > 0 && name_before(missing[position], missing[position - 1]) {
                    let previous = missing[position - 1];
                    missing[position - 1] = missing[position]; missing[position] = previous;
                    position -= 1;
                }
            }
        }
        var message = "Switch must be exhaustive, missing cases: ";
        if domain.equals("optional") { message = "Switch on Optional must be exhaustive, missing: "; }
        self.report_error(TypeErrorKind.non_exhaustive_match(), message + join_strings(missing, ", "));
    }
    // Numbers, strings and other unbounded values: a switch producing a value
    // needs `default` or a pattern matching anything.
    def require_catch_all(cases: Vec<NodeId>, expression: Bool, value_type: TypeId) -> Void {
        if !expression || self.type_table.is_error(value_type) { return; }
        for item in cases { if let branch = self.arena.get(item) { switch branch.form {
            case .switch_case(let data):
                for pair in data.patterns {
                    if let guard_expr = pair.1 { continue; }
                    if self.irrefutable(pair.0) { return; }
                }
            default: {}
        } } }
        self.report_error(TypeErrorKind.non_exhaustive_match(), f"A switch expression over {self.type_table.format_type(value_type)} must be exhaustive: add a `default` case");
    }
    def irrefutable(id: NodeId) -> Bool {
        guard let node = self.arena.get(id) else { return false; }
        switch node.form {
            case .identifier_pattern(_), .wildcard_pattern: return true;
            case .typed_pattern(let data):
                if let pattern = data.pattern { return self.irrefutable(pattern); }
                return true;
            case .tuple_pattern(let data):
                for element in data.elements { if !self.irrefutable(element.1) { return false; } }
                return true;
            default: return false;
        }
    }
    def coverage(id: NodeId, domain: String) -> PatternCoverage {
        let names = Vec<String>.new();
        guard let node = self.arena.get(id) else { return PatternCoverage.values(names); }
        switch node.form {
            case .identifier_pattern(_), .wildcard_pattern: return PatternCoverage.catch_all();
            case .enum_case_pattern(let data):
                if domain.equals("bool") { return PatternCoverage.values(names); }
                if domain.equals("optional") {
                    if data.case_name.equals("None") || data.case_name.equals("nil") { names.push("none"); }
                    else if data.case_name.equals("Some") {
                        var full = true;
                        for pattern in data.payload { if !self.irrefutable(pattern) { full = false; } }
                        if full { names.push("some"); }
                    }
                } else {
                    var full = true;
                    for pattern in data.payload { if !self.irrefutable(pattern) { full = false; } }
                    if full { names.push(data.case_name); }
                }
            case .literal_pattern(let data):
                if let range = data.upper { return PatternCoverage.values(names); }
                if let literal = data.value {
                    if let value = self.arena.get(literal) {
                        switch value.form {
                            case .literal(let item):
                                if domain.equals("optional") && item.kind.equals("nil") { names.push("none"); }
                                if domain.equals("bool") && item.kind.equals("bool") {
                                    switch item.value { case .boolean(let flag): names.push(flag.to_string()); default: {} }
                                }
                            default: {}
                        }
                    }
                }
            case .or_pattern(let data):
                for pattern in data.patterns {
                    switch self.coverage(pattern, domain) {
                        case .catch_all: return PatternCoverage.catch_all();
                        case .values(let values): for name in values { names.push(name); }
                    }
                }
            case .typed_pattern(let data): if let inner = data.pattern { return self.coverage(inner, domain); }
            default: {}
        }
        PatternCoverage.values(names)
    }
}

def optional_case_display(name: String) -> String {
    if name.equals("some") { return "Some(...)"; }
    "nil"
}
