// Protocol requirements, witnesses and extension-aware conformance caching.
pub import "type_resolver.rl"

pub struct WitnessEntry {
    pub var requirement_name: String;
    pub var implementation_symbol: SymbolId?;
    pub var implementation_name: String;
    pub var is_method: Bool;
}
pub struct ConformanceResult {
    pub var conforms: Bool;
    pub let witnesses: Vec<WitnessEntry>;
    pub let missing_requirements: Vec<String>;
    pub let errors: Vec<String>;
    pub static def new() -> ConformanceResult {
        ConformanceResult { conforms: false, witnesses: Vec<WitnessEntry>.new(),
            missing_requirements: Vec<String>.new(), errors: Vec<String>.new() }
    }
}
struct ConformanceExtension {
    let concrete: TypeId;
    let protocol: TypeId;
    let symbols: Vec<SymbolId>;
}
pub struct ConformanceChecker {
    pub let arena: AstArena;
    pub let type_table: TypeTable;
    pub let symbol_table: SymbolTable;
    let cache: Dict<String, ConformanceResult>;
    let extensions: Vec<ConformanceExtension>;
    pub static def new(arena: AstArena, type_table: TypeTable, symbol_table: SymbolTable) -> ConformanceChecker {
        ConformanceChecker { arena, type_table, symbol_table,
            cache: Dict<String, ConformanceResult>.with_capacity(16, 1), extensions: Vec<ConformanceExtension>.new() }
    }
    pub def register_extension(concrete: TypeId, protocol: TypeId, symbol: SymbolId) -> Void {
        var found = false;
        for entry in self.extensions {
            if entry.concrete == concrete && entry.protocol == protocol {
                entry.symbols.push(symbol); found = true; break;
            }
        }
        if !found { self.extensions.push(ConformanceExtension { concrete, protocol, symbols: [symbol] }); }
        // Witness lookup searches every extension for a concrete type, including
        // extensions registered against a different protocol.
        let prefix = concrete.id.to_string() + ":";
        let stale = Vec<String>.new();
        for entry in self.cache.entries() { if entry.key.starts_with(prefix) { stale.push(entry.key); } }
        for key in stale { self.cache.remove(key); }
    }
    pub def check_conformance(concrete: TypeId, protocol: TypeId) -> ConformanceResult {
        let key = f"{concrete.id}:{protocol.id}";
        if let cached = self.cache[key] { return cached; }
        let result = self.check_impl(concrete, protocol);
        self.cache[key] = result;
        result
    }
    def check_impl(concrete: TypeId, protocol: TypeId) -> ConformanceResult {
        let result = ConformanceResult.new();
        guard let info = self.type_table.get_type(protocol) else {
            result.errors.push(f"Not a protocol type: TypeId({protocol.id})"); return result;
        }
        var requirements: ProtocolTypeData? = nil;
        switch info.data { case .protocol(let data): requirements = data; default: {} }
        guard let data = requirements else {
            result.errors.push(f"Not a protocol type: TypeId({protocol.id})"); return result;
        }
        var known = false;
        if let actual = self.type_table.get_type(concrete) { known = true; }
        if !known { result.errors.push(f"Unknown type: TypeId({concrete.id})"); return result; }
        for requirement in data.func_requirements {
            if let witness = self.find_func_witness(concrete, requirement, result.errors) { result.witnesses.push(witness); }
            else if !has_error_prefix(result.errors, f"Method '{requirement.name}' ") { result.missing_requirements.push(requirement.name); }
        }
        for requirement in data.prop_requirements {
            if let witness = self.find_prop_witness(concrete, requirement, result.errors) { result.witnesses.push(witness); }
            else if !has_error_prefix(result.errors, f"Property '{requirement.name}' ") { result.missing_requirements.push(requirement.name); }
        }
        result.conforms = result.missing_requirements.len() == 0 && result.errors.len() == 0;
        result
    }
    def type_members(concrete: TypeId) -> Vec<NodeId>? {
        guard let info = self.type_table.get_type(concrete) else { return nil; }
        var symbol_id: SymbolId? = nil;
        switch info.data {
            case .struct_type(let data): symbol_id = data.symbol_id;
            case .enum_type(let data): symbol_id = data.symbol_id;
            default: {}
        }
        guard let id = symbol_id else { return nil; }
        guard let symbol = self.symbol_table.get_symbol(id) else { return nil; }
        guard let decl = symbol.decl_node else { return nil; }
        guard let node = self.arena.get(decl) else { return nil; }
        switch node.form {
            case .struct_decl(let data): data.members;
            case .enum_decl(let data): data.members;
            default: nil;
        }
    }
    def witness(id: NodeId, name: String, method: Bool) -> WitnessEntry {
        WitnessEntry { requirement_name: name, implementation_symbol: self.symbol_table.get_symbol_by_node(id),
            implementation_name: name, is_method: method }
    }
    def find_func_in(members: Vec<NodeId>, requirement: FuncRequirement, errors: Vec<String>) -> WitnessEntry? {
        for id in members {
            if let node = self.arena.get(id) {
                switch node.form {
                    case .func_decl(let func):
                        if func.name.equals(requirement.name) {
                            if let mismatch = self.func_mismatch(func, requirement) {
                                errors.push(f"Method '{requirement.name}' {mismatch}"); return nil;
                            }
                            return self.witness(id, func.name, true);
                        }
                    default: {}
                }
            }
        }
        nil
    }
    def find_func_witness(concrete: TypeId, requirement: FuncRequirement, errors: Vec<String>) -> WitnessEntry? {
        guard let members = self.type_members(concrete) else { return nil; }
        let original_errors = errors.len();
        if let witness = self.find_func_in(members, requirement, errors) { return witness; }
        if errors.len() != original_errors { return nil; }
        for entry in self.extensions {
            if entry.concrete != concrete { continue; }
            for symbol_id in entry.symbols {
                if let symbol = self.symbol_table.get_symbol(symbol_id) {
                    if let id = symbol.decl_node {
                        if let node = self.arena.get(id) {
                            switch node.form {
                                case .extension_decl(let data):
                                    if let witness = self.find_func_in(data.members, requirement, errors) { return witness; }
                                    if errors.len() != original_errors { return nil; }
                                default: {}
                            }
                        }
                    }
                }
            }
        }
        nil
    }
    def find_prop_witness(concrete: TypeId, requirement: PropRequirement, errors: Vec<String>) -> WitnessEntry? {
        guard let members = self.type_members(concrete) else { return nil; }
        for id in members {
            if let node = self.arena.get(id) {
                switch node.form {
                    case .property_decl(let prop):
                        if !prop.name.equals(requirement.name) { continue; }
                        if requirement.has_setter && !prop.is_mutable {
                            errors.push(f"Property '{requirement.name}' must be mutable to satisfy set requirement"); return nil;
                        }
                        var actual: TypeId? = nil;
                        if let annotation = prop.type_annotation { actual = self.resolve_ast_type(annotation); }
                        var matches = false;
                        var display = "unknown";
                        if let resolved = actual { matches = resolved == requirement.type_id; display = self.type_table.format_type(resolved); }
                        if !matches {
                            errors.push(f"Property '{requirement.name}' has type {display}, expected {self.type_table.format_type(requirement.type_id)}"); return nil;
                        }
                        return self.witness(id, prop.name, false);
                    default: {}
                }
            }
        }
        nil
    }
    def func_mismatch(func: FuncDeclAst, requirement: FuncRequirement) -> String? {
        if func.is_async != requirement.is_async {
            var expected = ""; var actual = "";
            if requirement.is_async { expected = "async "; }
            if func.is_async { actual = "async "; }
            return f"asyncness mismatch: expected {expected}function, got {actual}function";
        }
        if func.params.len() != requirement.params.len() {
            return f"parameter count mismatch: expected {requirement.params.len()}, got {func.params.len()}";
        }
        for index in 0..<func.params.len() {
            let actual = self.param_type(func.params[index]);
            let expected = requirement.params.get(index);
            if actual != expected { return f"parameter {index + 1} type mismatch: expected {self.type_table.format_type(expected)}, got {self.type_table.format_type(actual)}"; }
        }
        var actual = self.type_table.void_type;
        if let node = func.return_type { actual = self.resolve_ast_type(node); }
        if actual != requirement.return_type {
            return f"return type mismatch: expected {self.type_table.format_type(requirement.return_type)}, got {self.type_table.format_type(actual)}";
        }
        nil
    }
    def param_type(id: NodeId) -> TypeId {
        if let node = self.arena.get(id) {
            switch node.form { case .param(let param): return self.resolve_ast_type(param.type_annotation); default: {} }
        }
        self.type_table.error_type
    }
    // Resolve conformance annotations independently of
    // checker resolution (notably aliases and type variables are not accepted).
    pub def resolve_ast_type(id: NodeId?) -> TypeId {
        guard let type_node = id else { return self.type_table.error_type; }
        guard let node = self.arena.get(type_node) else { return self.type_table.error_type; }
        switch node.form {
            case .builtin_type(let data): return self.type_table.get_builtin(data.name) ?? self.type_table.error_type;
            case .named_type(let data):
                var symbol_id = self.symbol_table.get_builtin(data.name);
                if let builtin = symbol_id {} else { symbol_id = self.symbol_table.get_type_symbol(data.name); }
                let args = Vec<TypeId>.new();
                for arg in data.generic_args { args.push(self.resolve_ast_type(arg)); }
                if let sid = symbol_id {
                    if let symbol = self.symbol_table.get_symbol(sid) {
                        switch symbol.kind {
                            case .struct_type: return self.type_table.make_struct(sid, args);
                            case .enum_type: return self.type_table.make_enum(sid, args);
                            case .protocol: return self.type_table.get_protocol_type(sid);
                            case .builtin_type: return self.type_table.get_builtin(symbol.name) ?? self.type_table.error_type;
                            default: {}
                        }
                    }
                }
            case .optional_type(let data): if let inner = data.inner { return self.type_table.make_optional(self.resolve_ast_type(inner)); }
            case .array_type(let data):
                if let element = data.element {
                    if let symbol = self.symbol_table.get_type_symbol("Vec") { return self.type_table.make_struct(symbol, [self.resolve_ast_type(element)]); }
                }
            case .dict_type(let data):
                if let key = data.key {
                    if let value = data.value {
                        if let symbol = self.symbol_table.get_type_symbol("Dict") { return self.type_table.make_struct(symbol, [self.resolve_ast_type(key), self.resolve_ast_type(value)]); }
                    }
                }
            case .tuple_type(let data):
                let elements = Vec<(String?, TypeId)>.new();
                for element in data.elements { elements.push((element.0, self.resolve_ast_type(element.1))); }
                return self.type_table.make_tuple(elements);
            case .function_type(let data):
                let params = Vec<TypeId>.new();
                for param in data.params { params.push(self.resolve_ast_type(param)); }
                var result = self.type_table.void_type;
                if let ret = data.return_type { result = self.resolve_ast_type(ret); }
                return self.type_table.make_function(params, result, data.is_async);
            case .any_type(let data):
                if let protocol = data.protocol {
                    let resolved = self.resolve_ast_type(protocol);
                    if self.type_table.is_protocol(resolved) { return self.type_table.make_existential(resolved); }
                }
            case .pointer_type: return self.type_table.get_builtin("RawPtr") ?? self.type_table.error_type;
            default: {}
        }
        self.type_table.error_type
    }
    pub def get_all_conformances(concrete: TypeId) -> Vec<TypeId> {
        let result = Vec<TypeId>.new();
        for entry in self.extensions {
            if entry.concrete == concrete && self.check_conformance(concrete, entry.protocol).conforms { result.push(entry.protocol); }
        }
        result
    }
}
def has_error_prefix(errors: Vec<String>, prefix: String) -> Bool {
    for error in errors { if error.starts_with(prefix) { return true; } }
    false
}
pub def check_conformance(concrete: TypeId, protocol: TypeId, arena: AstArena, types: TypeTable, symbols: SymbolTable) -> ConformanceResult {
    ConformanceChecker.new(arena, types, symbols).check_conformance(concrete, protocol)
}
