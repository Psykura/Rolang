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
    // Witness type names: the conforming type's generic parameters mapped to its type
    // arguments, plus a witness method's generic parameters mapped to the requirement's.
    var generic_scope: Dict<String, TypeId>;
    var type_scope: Dict<String, TypeId>;
    // Associated type placeholders bound while checking one conformance, and the
    // requirement's own method generic names, which are not placeholders.
    var bindings: Dict<String, TypeId>;
    var method_generics: FrozenVec<String>;
    pub static def new(arena: AstArena, type_table: TypeTable, symbol_table: SymbolTable) -> ConformanceChecker {
        ConformanceChecker { arena, type_table, symbol_table,
            cache: Dict<String, ConformanceResult>.with_capacity(16, 1), extensions: Vec<ConformanceExtension>.new(),
            generic_scope: Dict<String, TypeId>.with_capacity(4, 1), type_scope: Dict<String, TypeId>.with_capacity(4, 1),
            bindings: Dict<String, TypeId>.with_capacity(4, 1), method_generics: FrozenVec<String>.empty() }
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
        self.bindings = Dict<String, TypeId>.with_capacity(4, 1);
        // `Self` in a requirement is the conforming type.
        self.bindings["Self"] = concrete;
        self.type_scope = self.type_arguments(concrete);
        for requirement in data.func_requirements {
            if let witness = self.find_func_witness(concrete, requirement, result.errors) { result.witnesses.push(witness); }
            else if !has_error_prefix(result.errors, f"Method '{requirement.name}' ") { result.missing_requirements.push(requirement.name); }
        }
        for requirement in data.prop_requirements {
            if let witness = self.find_prop_witness(concrete, requirement, result.errors) { result.witnesses.push(witness); }
            else if !has_error_prefix(result.errors, f"Property '{requirement.name}' ") { result.missing_requirements.push(requirement.name); }
        }
        // `P<A>` fixes its primary associated types; its requirements already use A.
        for index in 0..<data.argument_names.len() { if !self.bindings.contains(data.argument_names.get(index)) { self.bindings[data.argument_names.get(index)] = data.arguments.get(index); } }
        if result.missing_requirements.len() == 0 && result.errors.len() == 0 {
            for name in self.associated_names(data.symbol_id) { if !self.bindings.contains(name) {
                result.errors.push(f"Cannot infer associated type '{name}' from the conforming members");
            } }
        }
        result.conforms = result.missing_requirements.len() == 0 && result.errors.len() == 0;
        if result.conforms { for entry in self.bindings.entries() { self.type_table.bind_associated(concrete, entry.key, entry.value); } }
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
        guard let members = self.type_members(concrete) else { return self.builtin_operator(concrete, requirement); }
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
    // Numbers and Bool satisfy operator requirements such as `__lt__(other: Self) -> Bool`
    // with their built-in operators.
    def builtin_operator(concrete: TypeId, requirement: FuncRequirement) -> WitnessEntry? {
        guard let info = self.type_table.get_type(concrete) else { return nil; }
        var numeric = false; var integer = false; var boolean = false;
        switch info.data {
            case .primitive(let primitive):
                integer = primitive.integer_width() > 0; numeric = integer || primitive.is_float();
                switch primitive { case .bool_type: boolean = true; default: {} }
            default: return nil;
        }
        if requirement.params.len() != 1 || requirement.is_async || requirement.generic_params.len() > 0 { return nil; }
        if !self.matches(concrete, requirement.params.get(0)) { return nil; }
        let name = requirement.name;
        var comparison = false; var supported = false;
        switch name {
            case "__eq__", "__ne__": comparison = true; supported = numeric || boolean;
            case "__lt__", "__le__", "__gt__", "__ge__": comparison = true; supported = numeric;
            case "__add__", "__sub__", "__mul__", "__truediv__", "__mod__": supported = numeric;
            case "__and__", "__or__", "__xor__", "__lshift__", "__rshift__": supported = integer;
            default: {}
        }
        if !supported { return nil; }
        var result = concrete;
        if comparison { result = self.type_table.get_builtin("Bool") ?? self.type_table.error_type; }
        if !self.matches(result, requirement.return_type) { return nil; }
        WitnessEntry { requirement_name: name, implementation_symbol: nil, implementation_name: name, is_method: true }
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
                        if let resolved = actual { matches = self.matches(resolved, requirement.type_id); display = self.type_table.format_type(resolved); }
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
        if func.generic_params.len() != requirement.generic_params.len() {
            return f"generic parameter count mismatch: expected {requirement.generic_params.len()}, got {func.generic_params.len()}";
        }
        self.generic_scope = Dict<String, TypeId>.with_capacity(4, 1); self.method_generics = requirement.generic_params;
        defer { self.generic_scope = Dict<String, TypeId>.with_capacity(4, 1); self.method_generics = FrozenVec<String>.empty(); }
        for index in 0..<func.generic_params.len() { if let node = self.arena.get(func.generic_params[index]) { switch node.form {
            case .generic_param(let param): self.generic_scope[param.name] = self.type_table.make_type_variable(requirement.generic_params.get(index));
            default: {}
        } } }
        for index in 0..<func.params.len() {
            let actual = self.param_type(func.params[index]);
            let expected = requirement.params.get(index);
            if !self.matches(actual, expected) { return f"parameter {index + 1} type mismatch: expected {self.type_table.format_type(expected)}, got {self.type_table.format_type(actual)}"; }
        }
        var actual = self.type_table.void_type;
        if let node = func.return_type { actual = self.resolve_ast_type(node); }
        if !self.matches(actual, requirement.return_type) {
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
    // Compares a witness type with a requirement type, binding associated type placeholders
    // (requirement type variables other than the method's own generic parameters).
    def matches(actual: TypeId, expected: TypeId) -> Bool {
        if actual == expected { return true; }
        guard let want = self.type_table.get_type(expected) else { return false; }
        guard let have = self.type_table.get_type(actual) else { return false; }
        switch want.data {
            case .type_variable(let variable):
                var generic = false; for name in self.method_generics { if name.equals(variable.name) { generic = true; } }
                if !generic {
                    if let bound = self.bindings[variable.name] { return self.type_table.types_equal(actual, bound); }
                    if self.type_table.is_error(actual) { return false; }
                    self.bindings[variable.name] = actual; return true;
                }
            case .optional(let inner): switch have.data { case .optional(let other): return self.matches(other, inner); default: {} }
            case .function(let x): switch have.data { case .function(let y):
                if x.is_async != y.is_async || x.params.len() != y.params.len() { return false; }
                for index in 0..<x.params.len() { if !self.matches(y.params.get(index), x.params.get(index)) { return false; } }
                return self.matches(y.return_type, x.return_type);
                default: {}
            }
            case .struct_type(let x): switch have.data { case .struct_type(let y):
                if let symbol = x.symbol_id { if let other = y.symbol_id { if symbol != other || x.type_args.len() != y.type_args.len() { return false; }
                    for index in 0..<x.type_args.len() { if !self.matches(y.type_args.get(index), x.type_args.get(index)) { return false; } }
                    return true;
                } }
                let xf = x.anon_fields ?? FrozenVec<TupleField>.empty(); let yf = y.anon_fields ?? FrozenVec<TupleField>.empty();
                if x.symbol_id == nil && y.symbol_id == nil && xf.len() == yf.len() {
                    for index in 0..<xf.len() { if !self.matches(yf.get(index).type_id, xf.get(index).type_id) { return false; } }
                    return true;
                }
                default: {}
            }
            case .enum_type(let x): switch have.data { case .enum_type(let y):
                if x.symbol_id != y.symbol_id || x.type_args.len() != y.type_args.len() { return false; }
                for index in 0..<x.type_args.len() { if !self.matches(y.type_args.get(index), x.type_args.get(index)) { return false; } }
                return true;
                default: {}
            }
            default: {}
        }
        self.type_table.types_equal(actual, expected)
    }
    // Generic parameter names of a concrete struct/enum mapped to its type arguments.
    pub def type_arguments(concrete: TypeId) -> Dict<String, TypeId> {
        let scope = Dict<String, TypeId>.with_capacity(4, 1);
        guard let info = self.type_table.get_type(concrete) else { return scope; }
        var symbol_id: SymbolId? = nil; var args = FrozenVec<TypeId>.empty();
        switch info.data { case .struct_type(let data): symbol_id = data.symbol_id; args = data.type_args; case .enum_type(let data): symbol_id = data.symbol_id; args = data.type_args; default: {} }
        guard let sid = symbol_id else { return scope; }
        guard let symbol = self.symbol_table.get_symbol(sid) else { return scope; }
        guard let decl = symbol.decl_node else { return scope; }
        guard let node = self.arena.get(decl) else { return scope; }
        var params = Vec<NodeId>.new();
        switch node.form { case .struct_decl(let data): params = data.generic_params; case .enum_decl(let data): params = data.generic_params; default: {} }
        for index in 0..<params.len() { if index < args.len() { if let param = self.arena.get(params[index]) { switch param.form {
            case .generic_param(let data): scope[data.name] = args.get(index);
            default: {}
        } } } }
        scope
    }
    // Associated type names declared by a protocol or the protocols it inherits.
    pub def associated_names(protocol_symbol: SymbolId) -> Vec<String> {
        let names = Vec<String>.new(); self.collect_associated(protocol_symbol, names, 0); names
    }
    def collect_associated(protocol_symbol: SymbolId, names: Vec<String>, depth: i32) -> Void {
        if depth > 16 { return; }
        guard let symbol = self.symbol_table.get_symbol(protocol_symbol) else { return; }
        guard let decl = symbol.decl_node else { return; }
        guard let node = self.arena.get(decl) else { return; }
        switch node.form { case .protocol_decl(let data):
            // Primary associated types (`protocol P<Item>`) come first, then associatedtype members.
            for param in data.generic_params { if let child = self.arena.get(param) { switch child.form {
                case .generic_param(let generic): var present = false; for name in names { if name.equals(generic.name) { present = true; } } if !present { names.push(generic.name); }
                default: {}
            } } }
            for member in data.members { if let child = self.arena.get(member) { switch child.form {
                case .associated_type_decl(let assoc): var present = false; for name in names { if name.equals(assoc.name) { present = true; } } if !present { names.push(assoc.name); }
                default: {}
            } } }
            // Parents from `protocol B: A`, stored as `where Self: A`.
            for id in data.constraints { if let constraint = self.arena.get(id) { switch constraint.form { case .constraint(let value): for bound in value.bounds {
                if let info = self.type_table.get_type(self.resolve_ast_type(bound)) { switch info.data { case .protocol(let parent): self.collect_associated(parent.symbol_id, names, depth + 1); default: {} } }
            } default: {} } } }
            default: {}
        }
    }
    // Resolve conformance annotations independently of
    // checker resolution (notably aliases and type variables are not accepted).
    pub def resolve_ast_type(id: NodeId?) -> TypeId {
        guard let type_node = id else { return self.type_table.error_type; }
        guard let node = self.arena.get(type_node) else { return self.type_table.error_type; }
        switch node.form {
            case .builtin_type(let data): return self.type_table.get_builtin(data.name) ?? self.type_table.error_type;
            case .named_type(let data):
                if data.generic_args.len() == 0 && data.module_path.len() == 0 {
                    if let scoped = self.generic_scope[data.name] { return scoped; }
                    if let scoped = self.type_scope[data.name] { return scoped; }
                }
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
