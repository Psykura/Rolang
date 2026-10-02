// AST type annotations to canonical TypeIds.
pub import "ast.rl"
pub import "symbols.rl"
pub import "types.rl"
import std.collections

pub struct TypeResolver {
    pub let arena: AstArena;
    pub let type_table: TypeTable;
    pub let symbol_table: SymbolTable;
    pub let node_symbols: Dict<i32, SymbolId>;
    pub let imported_symbols: Dict<String, SymbolId>;
    pub let error_reporter: ((String, String, NodeId?) -> Void)?;
    pub let allow_symbol_table_lookup: Bool;
    let resolving_aliases: Dict<i32, Bool>;

    pub static def new(arena: AstArena, type_table: TypeTable, symbol_table: SymbolTable,
                       node_symbols: Dict<i32, SymbolId>? = nil,
                       imported_symbols: Dict<String, SymbolId>? = nil,
                       error_reporter: ((String, String, NodeId?) -> Void)? = nil,
                       allow_symbol_table_lookup: Bool = false) -> TypeResolver {
        TypeResolver {
            arena, type_table, symbol_table,
            node_symbols: node_symbols ?? Dict<i32, SymbolId>.with_capacity(16, 0),
            imported_symbols: imported_symbols ?? Dict<String, SymbolId>.with_capacity(16, 1),
            error_reporter, allow_symbol_table_lookup,
            resolving_aliases: Dict<i32, Bool>.with_capacity(16, 0)
        }
    }

    def report(kind: String, message: String, node: NodeId? = nil) -> Void {
        if let callback = self.error_reporter { callback(kind, message, node); }
    }

    pub def lookup_named_struct(name: String) -> SymbolId? {
        if let symbol = self.imported_symbols[name] { return symbol; }
        self.symbol_table.get_type_symbol(name)
    }

    pub def make_vec_type(element: TypeId) -> TypeId {
        guard let symbol = self.lookup_named_struct("Vec") else {
            self.report("NOT_A_TYPE", "Vec<T> is not in scope; ensure 'vec.rl' is imported.");
            return self.type_table.error_type;
        }
        self.type_table.make_struct(symbol, [element])
    }

    pub def make_dict_type(key: TypeId, value: TypeId) -> TypeId {
        guard let symbol = self.lookup_named_struct("Dict") else {
            self.report("NOT_A_TYPE", "Dict<K, V> is not in scope; ensure 'dict.rl' is imported.");
            return self.type_table.error_type;
        }
        self.type_table.make_struct(symbol, [key, value])
    }

    pub def resolve_type_node(type_node: NodeId?, subst: Dict<String, TypeId>? = nil) -> TypeId {
        self.resolve(type_node, subst)
    }

    pub def resolve(type_node: NodeId?, subst: Dict<String, TypeId>? = nil) -> TypeId {
        guard let id = type_node else { return self.type_table.error_type; }
        guard let node = self.arena.get(id) else { return self.type_table.error_type; }
        switch node.form {
            case .builtin_type(let data):
                if let builtin = self.type_table.get_builtin(data.name) { return builtin; }
                self.report("NOT_A_TYPE", f"Unknown type '{data.name}'");
            case .named_type(_): return self.resolve_named(id, subst);
            case .optional_type(let data):
                if let inner = data.inner { return self.type_table.make_optional(self.resolve(inner, subst)); }
            case .array_type(let data):
                if let element = data.element { return self.make_vec_type(self.resolve(element, subst)); }
            case .dict_type(let data):
                if let key = data.key {
                    if let value = data.value {
                        return self.make_dict_type(self.resolve(key, subst), self.resolve(value, subst));
                    }
                }
            case .tuple_type(let data):
                let elements = Vec<(String?, TypeId)>.new();
                for element in data.elements {
                    elements.push((element.0, self.resolve(element.1, subst)));
                }
                return self.type_table.make_tuple(elements);
            case .function_type(let data):
                let params = Vec<TypeId>.new();
                for param in data.params { params.push(self.resolve(param, subst)); }
                var result = self.type_table.void_type;
                if let return_node = data.return_type { result = self.resolve(return_node, subst); }
                return self.type_table.make_function(params, result, data.is_async);
            case .any_type(let data):
                if let protocol = data.protocol {
                    let protocol_type = self.resolve_named(protocol, subst);
                    if self.type_table.is_protocol(protocol_type) {
                        return self.type_table.make_existential(protocol_type);
                    }
                    if let candidate = self.arena.get(protocol) {
                        switch candidate.form {
                            case .named_type(let named):
                                self.report("NOT_A_TYPE", f"'{named.name}' is not a protocol", protocol);
                            default: {}
                        }
                    }
                }
            case .pointer_type:
                return self.type_table.get_builtin("RawPtr") ?? self.type_table.error_type;
            default: {}
        }
        self.type_table.error_type
    }

    pub def resolve_named(named_id: NodeId, subst: Dict<String, TypeId>? = nil) -> TypeId {
        guard let node = self.arena.get(named_id) else { return self.type_table.error_type; }
        guard let named = named_form(node) else { return self.type_table.error_type; }

        if named.module_path.len() == 0 && named.generic_args.len() == 0 {
            if let replacements = subst {
                if let replacement = replacements[named.name] { return replacement; }
            }
        }

        if named.module_path.len() == 1 && named.generic_args.len() == 0 { if let base = self.node_symbols[named_id.id] {
            if let symbol = self.symbol_table.get_symbol(base) { switch symbol.kind { case .generic_param:
                // Projection `C.Item`: substituted with C's binding, or kept as a named type variable.
                let projection = symbol.name + "." + named.name;
                // A bound such as `C: Container<i32>` fixes C.Item.
                if let fixed = self.bound_argument(symbol, named.name, subst) { return fixed; }
                if !self.declares_associated(symbol, named.name) {
                    self.report("NOT_A_TYPE", f"Generic parameter '{symbol.name}' has no associated type '{named.name}'", named_id);
                    return self.type_table.error_type;
                }
                if let replacements = subst {
                    if let replacement = replacements[projection] { return replacement; }
                    if let projected = self.type_table.project(projection, replacements) { return projected; }
                }
                return self.type_table.make_type_variable(projection);
                default: {}
            } }
        } }
        guard let symbol_id = self.lookup_named_symbol(named, named_id) else {
            if let builtin = self.type_table.get_builtin(named.name) { return builtin; }
            var display = named.name;
            if named.module_path.len() > 0 {
                display = join_strings(named.module_path, ".") + "." + named.name;
            }
            self.report("NOT_A_TYPE", f"Unknown type '{display}'", named_id);
            return self.type_table.error_type;
        }
        guard let symbol = self.symbol_table.get_symbol(symbol_id) else {
            return self.type_table.error_type;
        }

        let type_args = Vec<TypeId>.new();
        for arg in named.generic_args { type_args.push(self.resolve(arg, subst)); }

        switch symbol.kind {
            case .type_alias:
                guard let declaration = self.alias_decl(symbol) else { return self.type_table.error_type; }
                let params = declaration.generic_params;
                if type_args.len() != params.len() {
                    var message = f"Type alias '{symbol.name}' does not accept generic arguments";
                    if params.len() > 0 {
                        message = f"Type alias '{symbol.name}' expects {params.len()} generic argument(s), got {type_args.len()}";
                    }
                    self.report("GENERIC_ARG_COUNT", message, named_id);
                    return self.type_table.error_type;
                }
                if self.resolving_aliases.contains(symbol_id.id) {
                    self.report("NOT_A_TYPE", f"Cyclic type alias '{symbol.name}'", named_id);
                    return self.type_table.error_type;
                }
                self.resolving_aliases[symbol_id.id] = true;
                defer { self.resolving_aliases.remove(symbol_id.id); }
                let alias_subst = Dict<String, TypeId>.with_capacity(16, 1);
                for i in 0..<params.len() {
                    if let param = self.arena.get(params[i]) {
                        switch param.form {
                            case .generic_param(let data): alias_subst[data.name] = type_args[i];
                            default: {}
                        }
                    }
                }
                return self.resolve(declaration.aliased_type, alias_subst);
            case .struct_type:
                if named.generic_args.len() > 0 {
                    if let arity = self.generic_arity(symbol) {
                        if type_args.len() != arity {
                            self.report("GENERIC_ARG_COUNT", f"Struct '{symbol.name}' expects {arity} generic argument(s), got {type_args.len()}", named_id);
                            return self.type_table.error_type;
                        }
                    }
                }
                return self.type_table.make_struct(symbol_id, type_args);
            case .enum_type:
                if named.generic_args.len() > 0 {
                    if let arity = self.generic_arity(symbol) {
                        if type_args.len() != arity {
                            self.report("GENERIC_ARG_COUNT", f"Enum '{symbol.name}' expects {arity} generic argument(s), got {type_args.len()}", named_id);
                            return self.type_table.error_type;
                        }
                    }
                }
                return self.type_table.make_enum(symbol_id, type_args);
            case .protocol:
                if type_args.len() == 0 { return self.type_table.get_protocol_type(symbol_id); }
                // `P<A>` fixes the protocol's primary associated types, declared as `protocol P<Item>`.
                let names = self.primary_associated(symbol);
                if names.len() != type_args.len() {
                    var expected = "no type arguments"; if names.len() > 0 { expected = f"{names.len()} type argument(s) for {join_strings(names, ", ")}"; }
                    self.report("GENERIC_ARG_COUNT", f"Protocol '{symbol.name}' expects {expected}, got {type_args.len()}", named_id);
                    return self.type_table.error_type;
                }
                return self.type_table.make_protocol_application(symbol_id, names, type_args);
            case .generic_param:
                let bounds = Vec<TypeId>.new();
                if let declaration = self.generic_param_decl(symbol) {
                    if let declared_bounds = declaration.bounds {
                        for bound in declared_bounds {
                            let resolved = self.resolve(bound, subst);
                            if !self.type_table.is_error(resolved) { bounds.push(resolved); }
                        }
                    }
                }
                return self.type_table.make_type_variable(symbol.name, bounds);
            case .associated_type:
                // Inside its protocol an associated type is a placeholder bound by each conformance.
                return self.type_table.make_type_variable(symbol.name);
            case .builtin_type:
                if let builtin = self.type_table.get_builtin(symbol.name) { return builtin; }
            default: {}
        }
        self.report("NOT_A_TYPE", f"'{named.name}' is not a type", named_id);
        self.type_table.error_type
    }

    def alias_decl(symbol: Symbol) -> TypeAliasDeclAst? {
        guard let id = symbol.decl_node else { return nil; }
        guard let node = self.arena.get(id) else { return nil; }
        switch node.form { case .type_alias_decl(let data): data; default: nil; }
    }

    def primary_associated(protocol: Symbol) -> Vec<String> {
        let names = Vec<String>.new();
        guard let decl = protocol.decl_node else { return names; }
        guard let node = self.arena.get(decl) else { return names; }
        switch node.form { case .protocol_decl(let data): for param in data.generic_params { if let child = self.arena.get(param) { switch child.form {
            case .generic_param(let generic): names.push(generic.name);
            default: {}
        } } } default: {} }
        names
    }
    def bound_argument(param: Symbol, name: String, subst: Dict<String, TypeId>?) -> TypeId? {
        guard let declaration = self.generic_param_decl(param) else { return nil; }
        guard let bounds = declaration.bounds else { return nil; }
        for bound in bounds { if let data = self.type_table.get_protocol_data(self.resolve(bound, subst)) {
            for index in 0..<data.argument_names.len() { if data.argument_names.get(index).equals(name) { return data.arguments.get(index); } }
        } }
        nil
    }
    // Whether a protocol bound of the generic parameter declares the associated type `name`.
    def declares_associated(param: Symbol, name: String) -> Bool {
        guard let declaration = self.generic_param_decl(param) else { return false; }
        guard let bounds = declaration.bounds else { return false; }
        for bound in bounds { if let sid = self.node_symbols[bound.id] { if self.protocol_declares(sid, name, 0) { return true; } } }
        false
    }
    def protocol_declares(protocol: SymbolId, name: String, depth: i32) -> Bool {
        if depth > 16 { return false; }
        guard let symbol = self.symbol_table.get_symbol(protocol) else { return false; }
        guard let decl = symbol.decl_node else { return false; }
        guard let node = self.arena.get(decl) else { return false; }
        switch node.form { case .protocol_decl(let data):
            for param in data.generic_params { if let child = self.arena.get(param) { switch child.form { case .generic_param(let generic): if generic.name.equals(name) { return true; } default: {} } } }
            for member in data.members { if let child = self.arena.get(member) { switch child.form { case .associated_type_decl(let assoc): if assoc.name.equals(name) { return true; } default: {} } } }
            // Parents from `protocol B: A`, stored as `where Self: A`.
            for id in data.constraints { if let constraint = self.arena.get(id) { switch constraint.form { case .constraint(let value): for bound in value.bounds {
                if let parent = self.node_symbols[bound.id] { if self.protocol_declares(parent, name, depth + 1) { return true; } }
            } default: {} } } }
            default: {}
        }
        false
    }
    def generic_param_decl(symbol: Symbol) -> GenericParamAst? {
        guard let id = symbol.decl_node else { return nil; }
        guard let node = self.arena.get(id) else { return nil; }
        switch node.form { case .generic_param(let data): data; default: nil; }
    }

    def generic_arity(symbol: Symbol) -> i32? {
        guard let id = symbol.decl_node else { return nil; }
        guard let node = self.arena.get(id) else { return nil; }
        switch node.form {
            case .struct_decl(let data): data.generic_params.len();
            case .enum_decl(let data): data.generic_params.len();
            case .type_alias_decl(let data): data.generic_params.len();
            default: nil;
        }
    }

    def lookup_named_symbol(named: NamedTypeAst, named_id: NodeId) -> SymbolId? {
        if let symbol = self.node_symbols[named_id.id] { return symbol; }
        if named.module_path.len() > 0 {
            let qualified = join_strings(named.module_path, ".") + "." + named.name;
            if let symbol = self.imported_symbols[qualified] { return symbol; }
        }
        if let symbol = self.imported_symbols[named.name] { return symbol; }
        if self.allow_symbol_table_lookup && named.module_path.len() == 0 {
            if let symbol = self.symbol_table.get_type_symbol(named.name) { return symbol; }
            for entry in self.symbol_table.symbols.entries() {
                let symbol = entry.value;
                if symbol.name.equals(named.name) {
                    switch symbol.kind {
                        case .generic_param: return symbol.id;
                        default: {}
                    }
                }
            }
        }
        nil
    }
}

def named_form(node: AstNode) -> NamedTypeAst? {
    switch node.form { case .named_type(let data): data; default: nil; }
}

def enum_type_data(info: TypeInfo) -> EnumTypeData? {
    switch info.data { case .enum_type(let data): data; default: nil; }
}

def enum_decl_form(node: AstNode) -> EnumDeclAst? {
    switch node.form { case .enum_decl(let data): data; default: nil; }
}

// Result<T, E> uses named ok/err cases; payload order and type argument
// order are independent.
pub def result_payloads(type_id: TypeId, type_table: TypeTable,
                        symbol_table: SymbolTable, arena: AstArena,
                        resolver: TypeResolver) -> Dict<String, TypeId>? {
    guard let info = type_table.get_type(type_id) else { return nil; }
    guard let enum_data = enum_type_data(info) else { return nil; }
    guard let symbol = symbol_table.get_symbol(enum_data.symbol_id) else { return nil; }
    guard let decl_id = symbol.decl_node else { return nil; }
    guard let decl_node = arena.get(decl_id) else { return nil; }
    guard let declaration = enum_decl_form(decl_node) else { return nil; }

    let cases = Vec<EnumCaseDefAst>.new();
    for member_id in declaration.members {
        if let member = arena.get(member_id) {
            switch member.form {
                case .enum_case_decl(let group):
                    for case_id in group.cases {
                        if let item = arena.get(case_id) {
                            switch item.form {
                                case .enum_case_def(let data): cases.push(data);
                                default: {}
                            }
                        }
                    }
                default: {}
            }
        }
    }
    if cases.len() != 2 { return nil; }
    var ok: EnumCaseDefAst? = nil;
    var err: EnumCaseDefAst? = nil;
    for item in cases {
        if item.name.equals("ok") { ok = item; }
        if item.name.equals("err") { err = item; }
    }
    guard let ok_case = ok else { return nil; }
    guard let err_case = err else { return nil; }
    if ok_case.payload.len() != 1 || err_case.payload.len() != 1 { return nil; }

    let subst = Dict<String, TypeId>.with_capacity(16, 1);
    var i = 0;
    while i < declaration.generic_params.len() && i < enum_data.type_args.len() {
        if let param = arena.get(declaration.generic_params[i]) {
            switch param.form {
                case .generic_param(let data): subst[data.name] = enum_data.type_args.get(i);
                default: {}
            }
        }
        i += 1;
    }
    let result = Dict<String, TypeId>.with_capacity(2, 1);
    for item in cases {
        result[item.name] = resolver.resolve(item.payload[0].1, subst);
    }
    result
}
