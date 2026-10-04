// Lazy HIR specialization, keyed by original symbols and concrete type IDs.
pub import "hir_builder.rl"
import "generic_inference.rl"
import std.collections
pub struct InstanceKey {
    pub let symbol_id: SymbolId;
    pub let type_args: FrozenVec<TypeId>;
    pub static def new(symbol_id: SymbolId, args: Vec<TypeId>) -> InstanceKey { InstanceKey { symbol_id, type_args: FrozenVec<TypeId>.new(args) } }
    pub def key() -> String { var out = self.symbol_id.id.to_string() + ":"; for arg in self.type_args { out += arg.id.to_string() + ","; } out }
}
pub struct TypeSubstitution {
    pub let mapping: Dict<String, TypeId>;
    pub static def new(mapping: Dict<String, TypeId>? = nil) -> TypeSubstitution { TypeSubstitution { mapping: mapping ?? Dict<String, TypeId>.with_capacity(16, 1) } }
    pub def is_empty() -> Bool { self.mapping.len() == 0 }
    pub def apply(type: TypeId, table: TypeTable) -> TypeId {
        guard let info = table.get_type(type) else { return type; }
        switch info.data {
            case .type_variable(let data): return self.mapping[data.name] ?? (table.project(data.name, self.mapping) ?? type);
            case .struct_type(let data):
                if let sid = data.symbol_id { let args = Vec<TypeId>.new(); for arg in data.type_args { args.push(self.apply(arg, table)); } return table.make_struct(sid, args); }
                let fields = Vec<(String?, TypeId)>.new(); if let values = data.anon_fields { for field in values { let name: String? = field.name; fields.push((name, self.apply(field.type_id, table))); } } return table.make_tuple(fields);
            case .enum_type(let data): let args = Vec<TypeId>.new(); for arg in data.type_args { args.push(self.apply(arg, table)); } return table.make_enum(data.symbol_id, args);
            case .function(let data): let params = Vec<TypeId>.new(); for p in data.params { params.push(self.apply(p, table)); } return table.make_function(params, self.apply(data.return_type, table), data.is_async);
            case .optional(let inner): return table.make_optional(self.apply(inner, table));
            default: return type;
        }
    }
}
pub struct HirInstance {
    pub let key: InstanceKey;
    pub let original: HirId;
    pub let specialized: HirId;
    pub let mangled_name: String;
}
pub struct MonomorphizationResult {
    pub let ast: AstArena;
    pub let arena: HirArena;
    pub let program: HirId;
    pub let type_table: TypeTable;
    pub let symbol_table: SymbolTable;
    pub let function_instances: Dict<String, HirInstance>;
    pub let struct_instances: Dict<String, HirInstance>;
    pub let enum_instances: Dict<String, HirInstance>;
    pub let errors: Vec<String>;
    pub def has_errors() -> Bool { self.errors.len() > 0 }
}
pub def mangle_name(base: String, args: FrozenVec<TypeId>, types: TypeTable) -> String {
    var out = base; for arg in args { out += "_" + mangle_type(arg, types); } out
}
pub def mangle_type(type: TypeId, types: TypeTable) -> String {
    if let info = types.get_type(type) { switch info.data {
        case .primitive: return types.format_type(type);
        case .struct_type(let data):
            if let sid = data.symbol_id { return mangle_name(f"S{sid.id}", data.type_args, types); }
            var out = "Tuple"; if let fields = data.anon_fields { for field in fields { out += "_" + mangle_type(field.type_id, types); } } return out;
        case .enum_type(let data): return mangle_name(f"E{data.symbol_id.id}", data.type_args, types);
        case .optional(let inner): return "Opt_" + mangle_type(inner, types);
        case .function(let data):
            let params = Vec<String>.new(); for p in data.params { params.push(mangle_type(p, types)); }
            var prefix = "fn"; if data.is_async { prefix = "afn"; }
            return prefix + "_" + join_strings(params, "_") + "_to_" + mangle_type(data.return_type, types);
        case .closure(let data):
            let params = Vec<String>.new(); for p in data.params { params.push(mangle_type(p, types)); }
            let captures = Vec<String>.new(); for c in data.captures { captures.push(mangle_type(c, types)); }
            var prefix = "clo"; if data.is_async { prefix = "aclo"; }
            return prefix + "_" + join_strings(params, "_") + "_to_" + mangle_type(data.return_type, types) + "_c" + join_strings(captures, "_");
        case .existential(let data): return "any_" + mangle_type(data.protocol_id, types);
        case .protocol(let data):
            let args = Vec<String>.new(); for arg in data.arguments { args.push(mangle_type(arg, types)); }
            if args.len() == 0 { return f"P{data.symbol_id.id}"; }
            return f"P{data.symbol_id.id}_" + join_strings(args, "_");
        case .type_variable(let data): return "T" + data.name;
        default: {}
    } }
    "unknown"
}
pub struct Monomorphizer {
    pub let input: HirBuildResult;
    pub let arena: HirArena;
    pub let types: TypeTable;
    pub let symbols: SymbolTable;
    pub let errors: Vec<String>;
    pub let functions: Dict<String, HirInstance>;
    pub let structs: Dict<String, HirInstance>;
    pub let enums: Dict<String, HirInstance>;
    pub var max_instantiations: i32;
    let function_order: Vec<String>;
    let struct_order: Vec<String>;
    let enum_order: Vec<String>;
    let originals: Dict<i32, HirId>;
    let struct_originals: Dict<i32, HirId>;
    let enum_originals: Dict<i32, HirId>;
    let method_owners: Dict<i32, SymbolId>;
    // Generic methods keyed by "<type symbol>:<method name>", for calls whose receiver was a type parameter.
    let generic_methods: Dict<String, SymbolId>;
    let method_order: Vec<i32>;
    let special_symbols: Dict<String, SymbolId>;
    let function_queue: Vec<InstanceKey>;
    let struct_queue: Vec<InstanceKey>;
    let enum_queue: Vec<InstanceKey>;
    let queued_functions: Dict<String, Bool>;
    let queued_structs: Dict<String, Bool>;
    let queued_enums: Dict<String, Bool>;
    let layout: LayoutService;
    let resolver: TypeResolver;
    pub static def new(input: HirBuildResult) -> Monomorphizer {
        let resolver = TypeResolver.new(input.ast, input.type_table, input.symbol_table, nil, nil, nil, true);
        let result = Monomorphizer { input, arena: input.arena, types: input.type_table, symbols: input.symbol_table,
            errors: Vec<String>.new(), functions: Dict<String, HirInstance>.with_capacity(16, 1), structs: Dict<String, HirInstance>.with_capacity(16, 1), enums: Dict<String, HirInstance>.with_capacity(16, 1),
            function_order: Vec<String>.new(), struct_order: Vec<String>.new(), enum_order: Vec<String>.new(),
            originals: Dict<i32, HirId>.with_capacity(16, 0), struct_originals: Dict<i32, HirId>.with_capacity(16, 0), enum_originals: Dict<i32, HirId>.with_capacity(16, 0),
            method_owners: Dict<i32, SymbolId>.with_capacity(16, 0), generic_methods: Dict<String, SymbolId>.with_capacity(16, 1), method_order: Vec<i32>.new(), special_symbols: Dict<String, SymbolId>.with_capacity(16, 1),
            function_queue: Vec<InstanceKey>.new(), struct_queue: Vec<InstanceKey>.new(), enum_queue: Vec<InstanceKey>.new(),
            queued_functions: Dict<String, Bool>.with_capacity(16, 1), queued_structs: Dict<String, Bool>.with_capacity(16, 1), queued_enums: Dict<String, Bool>.with_capacity(16, 1),
            layout: LayoutService.new(input.ast, input.type_table, input.symbol_table, resolver), resolver, max_instantiations: 100000 };
        result.index_program(); result
    }
    def items() -> Vec<HirId> { if let node = self.arena.get(self.input.program) { switch node.form { case .program(let data): return data.items; default: {} } } Vec<HirId>.new() }
    def func(id: HirId) -> HirFunctionData? { if let node = self.arena.get(id) { switch node.form { case .function(let data): return data; default: {} } } nil }
    def decl_params(sid: SymbolId) -> Vec<NodeId> {
        if let sym = self.symbols.get_symbol(sid) { if let id = sym.decl_node { if let node = self.input.ast.get(id) { switch node.form { case .func_decl(let data): return data.generic_params; case .struct_decl(let data): return data.generic_params; case .enum_decl(let data): return data.generic_params; case .extension_decl(let data): return data.generic_params; default: {} } } } } Vec<NodeId>.new()
    }
    def param_name(id: NodeId) -> String { if let node = self.input.ast.get(id) { switch node.form { case .generic_param(let data): return data.name; default: {} } } "" }
    def generic_names(sid: SymbolId) -> Vec<String> {
        let out = Vec<String>.new(); if let owner = self.method_owners[sid.id] { for name in self.generic_names(owner) { out.push(name); } }
        for id in self.decl_params(sid) { out.push(self.param_name(id)); } out
    }
    def index_program() -> Void {
        for id in self.items() { if let node = self.arena.get(id) { switch node.form {
            case .function(let data): self.originals[data.symbol_id.id] = id;
            case .struct_type(let data): self.struct_originals[data.symbol_id.id] = id;
            case .enum_type(let data): self.enum_originals[data.symbol_id.id] = id;
            case .extension(let data): for method in data.methods { if let func = self.func(method) { self.originals[func.symbol_id.id] = method; } }
            default: {}
        } } }
        for pass in 0..<2 { for id in self.items() { if let node = self.arena.get(id) {
            var methods = Vec<HirId>.new(); var owner: SymbolId? = nil; var is_type = false;
            switch node.form { case .struct_type(let data): methods = data.methods; owner = data.symbol_id; is_type = true; case .enum_type(let data): methods = data.methods; owner = data.symbol_id; is_type = true; case .extension(let data): methods = data.methods; default: {} }
            if (pass == 0 && !is_type) || (pass == 1 && is_type) { continue; }
            var type_symbol = owner; switch node.form { case .extension(let data): type_symbol = self.type_symbol(data.extended_type); default: {} }
            for method in methods { if let func = self.func(method) {
                if let tsid = type_symbol { if self.decl_params(func.symbol_id).len() > 0 { self.generic_methods[f"{tsid.id}:{func.name}"] = func.symbol_id; } }
                if let sid = owner { if self.decl_params(func.symbol_id).len() > 0 { self.method_owners[func.symbol_id.id] = sid; self.method_order.push(func.symbol_id.id); self.originals[func.symbol_id.id] = method; } }
                else {
                    if let symbol = self.symbols.get_symbol(func.symbol_id) { if let decl = symbol.decl_node {
                        for candidate in self.symbols.symbols.values() { if let ref = candidate.decl_node { if let syntax = self.input.ast.get(ref) { switch syntax.form { case .extension_decl(let data):
                            var found = false; for member in data.members { if member == decl { found = true; } }
                            if found { if data.generic_params.len() > 0 || self.decl_params(func.symbol_id).len() > 0 { self.method_owners[func.symbol_id.id] = candidate.id; self.method_order.push(func.symbol_id.id); } break; }
                            default: {}
                        } } } }
                    } }
                }
            } }
        } } }
        // Methods of generic extensions are generic through their extension: calls
        // through a type parameter find them by receiver type and name.
        for id in self.items() { if let node = self.arena.get(id) { switch node.form {
            case .extension(let data):
                guard let tsid = self.type_symbol(data.extended_type) else { continue; }
                for method in data.methods { if let func = self.func(method) {
                    let key = f"{tsid.id}:{func.name}";
                    if self.method_owners.contains(func.symbol_id.id) && !self.generic_methods.contains(key) { self.generic_methods[key] = func.symbol_id; }
                } }
            default: {}
        } } }
        // Add explicit self parameters to standalone generic instance methods.
        for method_id in self.method_order { if let owner = self.method_owners[method_id] {
            if let id = self.originals[method_id] { if let method = self.func(id) { if !method.is_static {
                let variables = Vec<TypeId>.new(); let subst = Dict<String, TypeId>.with_capacity(16, 1);
                for param in self.decl_params(owner) { let name = self.param_name(param); let variable = self.types.make_type_variable(name); variables.push(variable); subst[name] = variable; }
                var receiver = self.types.error_type;
                if let sym = self.symbols.get_symbol(owner) { if let ref = sym.decl_node { if let node = self.input.ast.get(ref) { switch node.form { case .enum_decl: receiver = self.types.make_enum(owner, variables); case .extension_decl(let data): receiver = self.resolver.resolve(data.extended_type, subst); default: receiver = self.types.make_struct(owner, variables); } } } }
                var self_symbol = SymbolId { id: -1 };
                if let body = method.body { for child in self.arena.preorder(body) { if let n = self.arena.get(child) { switch n.form { case .var_ref(let v): if v.name.equals("self") { self_symbol = v.symbol_id; break; } default: {} } } } }
                let params = Vec<HirId>.new(); params.push(self.arena.add(HirForm.param(HirParamData { name: "self", symbol_id: self_symbol, type_id: receiver, external_name: nil, has_default: false }))); for param in method.params { params.push(param); }
                self.originals[method_id] = self.arena.copy_location(id, self.arena.add(HirForm.function(HirFunctionData { name: method.name, symbol_id: method.symbol_id, params, return_type: method.return_type, body: method.body, is_async: method.is_async, is_method: method.is_method, is_static: method.is_static })));
            } } }
        } }
    }
    def enqueue(kind: i32, key: InstanceKey) -> Void {
        let text = key.key();
        if kind == 0 { if !self.queued_functions.contains(text) { self.queued_functions[text] = true; self.function_queue.push(key); } }
        else if kind == 1 { if !self.queued_structs.contains(text) { self.queued_structs[text] = true; self.struct_queue.push(key); } }
        else { if !self.queued_enums.contains(text) { self.queued_enums[text] = true; self.enum_queue.push(key); } }
    }
    def seed() -> Void {
        for id in self.items() { if let node = self.arena.get(id) { switch node.form {
            case .function(let data): if self.generic_names(data.symbol_id).len() == 0 { self.enqueue(0, InstanceKey.new(data.symbol_id, Vec<TypeId>.new())); }
            case .struct_type(let data): if self.decl_params(data.symbol_id).len() == 0 { self.enqueue(1, InstanceKey.new(data.symbol_id, Vec<TypeId>.new())); }
            case .enum_type(let data): if self.decl_params(data.symbol_id).len() == 0 { self.enqueue(2, InstanceKey.new(data.symbol_id, Vec<TypeId>.new())); }
            case .extension(let data): for method in data.methods { if let func = self.func(method) { if self.generic_names(func.symbol_id).len() == 0 { self.enqueue(0, InstanceKey.new(func.symbol_id, Vec<TypeId>.new())); } } }
            default: {}
        } } }
    }
    pub def run() -> MonomorphizationResult {
        self.seed();
        for required in self.arena.required_methods { self.require_method(required.0, required.1); }
        var fi = 0; var si = 0; var ei = 0; var count = 0; var over_budget = false;
        while fi < self.function_queue.len() || si < self.struct_queue.len() || ei < self.enum_queue.len() {
            while fi < self.function_queue.len() { let key = self.function_queue[fi]; fi += 1; if !self.functions.contains(key.key()) { count += 1; if count > self.max_instantiations { over_budget = true; break; } self.instantiate(0, key); } }
            if over_budget { break; }
            while si < self.struct_queue.len() { let key = self.struct_queue[si]; si += 1; if !self.structs.contains(key.key()) { count += 1; if count > self.max_instantiations { over_budget = true; break; } self.instantiate(1, key); } }
            if over_budget { break; }
            while ei < self.enum_queue.len() { let key = self.enum_queue[ei]; ei += 1; if !self.enums.contains(key.key()) { count += 1; if count > self.max_instantiations { over_budget = true; break; } self.instantiate(2, key); } }
            if over_budget { break; }
        }
        if over_budget { self.errors.push(f"monomorphization exceeded the instantiation limit ({self.max_instantiations}); this usually indicates unbounded polymorphic recursion in a generic type or function"); }
        self.build_result()
    }
    def substitution(sid: SymbolId, args: FrozenVec<TypeId>) -> TypeSubstitution {
        let subst = TypeSubstitution.new(); let names = self.generic_names(sid);
        for index in 0..<names.len() { if index < args.len() { subst.mapping[names[index]] = args.get(index); } } subst
    }
    def special_symbol(key: InstanceKey, name: String) -> SymbolId {
        if let sid = self.special_symbols[key.key()] { return sid; }
        if key.type_args.len() == 0 { return key.symbol_id; }
        if let original = self.symbols.get_symbol(key.symbol_id) {
            let sym = self.symbols.create_symbol(name, original.kind, original.namespace, original.span, original.decl_node, original.is_mutable);
            self.special_symbols[key.key()] = sym.id; self.symbols.record_specialization(sym.id, original.id, key.type_args.to_vec()); return sym.id;
        }
        key.symbol_id
    }
    def specialized_type(type: TypeId, subst: TypeSubstitution) -> TypeId { self.nested(subst.apply(type, self.types)) }
    def nested(type: TypeId) -> TypeId {
        if let info = self.types.get_type(type) { switch info.data {
            case .struct_type(let data):
                if let sid = data.symbol_id {
                    let args = Vec<TypeId>.new(); for arg in data.type_args { args.push(self.nested(arg)); }
                    if args.len() > 0 && self.struct_originals.contains(sid.id) && !self.types.has_type_variables(type) {
                        let key = InstanceKey.new(sid, args); self.enqueue(1, key); var name = ""; if let original = self.struct_originals[sid.id] { if let node = self.arena.get(original) { switch node.form { case .struct_type(let d): name = d.name; default: {} } } }
                        return self.types.make_struct(self.special_symbol(key, mangle_name(name, key.type_args, self.types)));
                    }
                    return self.types.make_struct(sid, args);
                }
                let fields = Vec<(String?, TypeId)>.new(); if let values = data.anon_fields { for field in values { let name: String? = field.name; fields.push((name, self.nested(field.type_id))); } } return self.types.make_tuple(fields);
            case .enum_type(let data):
                let args = Vec<TypeId>.new(); for arg in data.type_args { args.push(self.nested(arg)); }
                if args.len() > 0 && self.enum_originals.contains(data.symbol_id.id) && !self.types.has_type_variables(type) {
                    let key = InstanceKey.new(data.symbol_id, args); self.enqueue(2, key); var name = ""; if let original = self.enum_originals[data.symbol_id.id] { if let node = self.arena.get(original) { switch node.form { case .enum_type(let d): name = d.name; default: {} } } }
                    return self.types.make_enum(self.special_symbol(key, mangle_name(name, key.type_args, self.types)));
                }
                return self.types.make_enum(data.symbol_id, args);
            case .optional(let inner): return self.types.make_optional(self.nested(inner));
            case .function(let data): let params = Vec<TypeId>.new(); for p in data.params { params.push(self.nested(p)); } return self.types.make_function(params, self.nested(data.return_type), data.is_async);
            default: {}
        } }
        type
    }
    def instantiate(kind: i32, key: InstanceKey) -> Void {
        let subst = self.substitution(key.symbol_id, key.type_args);
        if kind == 0 {
            guard let id = self.originals[key.symbol_id.id] else { return; }
            guard let original = self.func(id) else { return; }
            var base = original.name; if self.method_owners.contains(key.symbol_id.id) { base += f"$method{key.symbol_id.id}"; }
            let name = mangle_name(base, key.type_args, self.types); let sid = self.special_symbol(key, name);
            let specialized = self.specialize_function(id, subst, sid, name);
            self.functions[key.key()] = HirInstance { key, original: id, specialized, mangled_name: name }; self.function_order.push(key.key());
        } else if kind == 1 {
            guard let id = self.struct_originals[key.symbol_id.id] else { return; }
            guard let node = self.arena.get(id) else { return; }
            switch node.form { case .struct_type(let data):
                let name = mangle_name(data.name, key.type_args, self.types); let sid = self.special_symbol(key, name);
                let fields = Vec<HirId>.new(); for field in data.fields { fields.push(self.clone_node(field, subst)); }
                let methods = self.specialize_methods(data.methods, subst, sid, name);
                let specialized = self.arena.add(HirForm.struct_type(HirStructData { name, symbol_id: sid, fields, methods }));
                self.structs[key.key()] = HirInstance { key, original: id, specialized, mangled_name: name }; self.struct_order.push(key.key());
                default: {}
            }
        } else {
            guard let id = self.enum_originals[key.symbol_id.id] else { return; }
            guard let node = self.arena.get(id) else { return; }
            switch node.form { case .enum_type(let data):
                let name = mangle_name(data.name, key.type_args, self.types); let sid = self.special_symbol(key, name);
                let cases = Vec<HirId>.new(); for case_id in data.cases { cases.push(self.clone_node(case_id, subst)); }
                let methods = self.specialize_methods(data.methods, subst, sid, name);
                let specialized = self.arena.add(HirForm.enum_type(HirEnumData { name, symbol_id: sid, cases, methods }));
                self.enums[key.key()] = HirInstance { key, original: id, specialized, mangled_name: name }; self.enum_order.push(key.key());
                default: {}
            }
        }
    }
    def specialize_function(id: HirId, subst: TypeSubstitution, sid: SymbolId, name: String) -> HirId {
        guard let data = self.func(id) else { return id; }
        let params = Vec<HirId>.new(); for param in data.params { params.push(self.clone_node(param, subst)); }
        let return_type = self.specialized_type(data.return_type, subst); self.discover(return_type);
        var body: HirId? = nil; if let value = data.body { body = self.clone_node(value, subst); }
        self.arena.copy_location(id, self.arena.add(HirForm.function(HirFunctionData { name, symbol_id: sid, params, return_type, body, is_async: data.is_async, is_method: data.is_method, is_static: data.is_static })))
    }
    def specialize_methods(methods: Vec<HirId>, subst: TypeSubstitution, owner: SymbolId, name: String) -> Vec<HirId> {
        let out = Vec<HirId>.new();
        for id in methods { if let method = self.func(id) {
            if self.method_owners.contains(method.symbol_id.id) { continue; }
            let mangled = name + "_" + method.name;
            let sym = self.symbols.create_symbol(mangled, SymbolKind.function(), Namespace.value());
            var args = Vec<TypeId>.new(); if let origin = self.symbols.specialization_origin[owner.id] { args = origin.type_args.to_vec(); }
            self.symbols.record_specialization(sym.id, method.symbol_id, args);
            out.push(self.specialize_function(id, subst, sym.id, mangled));
        } }
        out
    }
    def arguments(args: Vec<(String?, HirId)>, subst: TypeSubstitution) -> Vec<(String?, HirId)> {
        let out = Vec<(String?, HirId)>.new(); for arg in args { let label: String? = arg.0; out.push((label, self.clone_node(arg.1, subst))); } out
    }
    def inference_arguments(args: Vec<(String?, HirId)>, subst: TypeSubstitution) -> Vec<TypeId> {
        let out = Vec<TypeId>.new(); for arg in args { out.push(subst.apply(self.arena.type_of(arg.1, self.types.error_type), self.types)); } out
    }
    // Clone every field through the generated schema. Ordering-sensitive forms
    // below retain the reference compiler's specialization and discovery order.
    def clone_node(id: HirId, subst: TypeSubstitution) -> HirId {
        self.arena.copy_location(id, self.clone_form(id, subst))
    }
    def clone_form(id: HirId, subst: TypeSubstitution) -> HirId {
        guard let node = self.arena.get(id) else { return id; }
        let new_type = self.specialized_type(node.form.type_id() ?? self.types.error_type, subst);
        switch node.form {
            case .binary_op(let data):
                if let call = self.operator_method(data, subst, new_type) { return call; }
            case .literal(let data):
                switch data.value { case .type_id(let target):
                    if data.kind.equals("size_of") || data.kind.equals("align_of") || data.kind.equals("type_id") {
                        let type = self.specialized_type(target, subst); var value: i64 = 0;
                        if data.kind.equals("size_of") { value = self.layout.size_of(type); }
                        else if data.kind.equals("align_of") { value = self.layout.align_of(type); }
                        else { value = self.types.runtime_type_id(type) as i64; }
                        return self.arena.add(HirForm.literal(HirLiteralData { type_id: new_type, value: HirValue.integer(value.to_string()), kind: "int" }));
                    }
                    default: {}
                }
                return self.arena.add(HirForm.literal(HirLiteralData { type_id: new_type, value: data.value, kind: data.kind }));
            case .call(let data): return self.specialize_call(id, data, subst, new_type);
            case .method_call(let data): return self.specialize_method_call(id, data, subst, new_type);
            case .param, .field, .var_decl: self.discover(new_type);
            case .enum_case(let data):
                let payload = Vec<(String?, TypeId)>.new(); for arg in data.payload { let type = self.specialized_type(arg.1, subst); self.discover(type); let label: String? = arg.0; payload.push((label, type)); }
                return self.arena.add(HirForm.enum_case(HirEnumCaseData { name: data.name, symbol_id: data.symbol_id, payload }));
            case .subscript(let data):
                let indices = Vec<HirId>.new(); for value in data.indices { indices.push(self.clone_node(value, subst)); }
                let object = self.clone_node(data.object, subst);
                return self.arena.add(HirForm.subscript(HirSubscriptData { type_id: new_type, object, indices }));
            case .array(let data):
                let element_type = self.specialized_type(data.element_type, subst); let elements = Vec<HirId>.new(); for value in data.elements { elements.push(self.clone_node(value, subst)); }
                self.discover(new_type); return self.arena.add(HirForm.array(HirArrayData { type_id: new_type, elements, element_type }));
            case .dict(let data):
                let key_type = self.specialized_type(data.key_type, subst); let value_type = self.specialized_type(data.value_type, subst);
                let entries = Vec<(HirId, HirId)>.new(); for entry in data.entries { let key = self.clone_node(entry.0, subst); let value = self.clone_node(entry.1, subst); entries.push((key, value)); }
                self.discover(new_type); return self.arena.add(HirForm.dict(HirDictData { type_id: new_type, entries, key_type, value_type }));
            case .struct_init(let data):
                let struct_type = self.specialized_type(data.struct_type, subst); self.discover(struct_type);
                return self.arena.add(HirForm.struct_init(HirStructInitData { type_id: new_type, struct_type, struct_symbol: data.struct_symbol, arguments: self.arguments(data.arguments, subst) }));
            case .enum_construct(let data):
                let enum_type = self.specialized_type(data.enum_type, subst); self.discover(enum_type);
                return self.arena.add(HirForm.enum_construct(HirEnumConstructData { type_id: new_type, enum_type, case_name: data.case_name, case_symbol: data.case_symbol, payload: self.arguments(data.payload, subst) }));
            case .cast(let data):
                let target_type = self.specialized_type(data.target_type, subst);
                return self.arena.add(HirForm.cast(HirCastData { type_id: new_type, expr: self.clone_node(data.expr, subst), target_type, kind: data.kind }));
            case .type_check(let data):
                let checked_type = self.specialized_type(data.checked_type, subst);
                return self.arena.add(HirForm.type_check(HirTypeCheckData { type_id: new_type, expr: self.clone_node(data.expr, subst), checked_type }));
            case .optional_some(let data):
                let inner_type = self.specialized_type(data.inner_type, subst);
                return self.arena.add(HirForm.optional_some(HirOptionalSomeData { type_id: new_type, value: self.clone_node(data.value, subst), inner_type }));
            case .optional_match(let data):
                let inner_type = self.specialized_type(data.inner_type, subst); let scrutinee = self.clone_node(data.scrutinee, subst);
                let some_expr = self.clone_node(data.some_expr, subst); let none_expr = self.clone_node(data.none_expr, subst);
                return self.arena.add(HirForm.optional_match(HirOptionalMatchData { type_id: new_type, scrutinee, inner_type, some_binding: data.some_binding, some_expr, none_expr }));
            case .enum_case_pattern(let data):
                let enum_type = self.specialized_type(data.enum_type, subst); self.discover(enum_type);
                let payload = Vec<HirId>.new(); for p in data.payload { payload.push(self.clone_node(p, subst)); }
                return self.arena.add(HirForm.enum_case_pattern(HirEnumCasePatternData { case_name: data.case_name, case_symbol: data.case_symbol, payload, enum_type }));
            default: {}
        }
        let child: (HirId) -> HirId = (value) -> { self.clone_node(value, subst) };
        let type: (TypeId) -> TypeId = (value) -> { self.specialized_type(value, subst) };
        self.arena.add(node.form.remap(child, type))
    }
    // An operator on a type parameter bounded by a protocol such as Comparable
    // becomes the requirement's method once the parameter is a struct or enum:
    // a < b calls a.__lt__(b); >, <= and >= use __lt__ and != uses __eq__.
    // Numbers keep their built-in operators.
    def operator_method(data: HirBinaryOpData, subst: TypeSubstitution, new_type: TypeId) -> HirId? {
        let original = self.arena.type_of(data.left, self.types.error_type);
        if !self.types.has_type_variables(original) { return nil; }
        let concrete = subst.apply(original, self.types);
        guard let info = self.types.get_type(concrete) else { return nil; }
        switch info.data {
            case .struct_type | .enum_type: {}
            case .optional(let inner):
                if data.op.equals("==") || data.op.equals("!=") { return self.optional_equality(self.clone_node(data.left, subst), self.clone_node(data.right, subst), data.op, inner, new_type); }
                return nil;
            default: return nil;
        }
        let method = to_method_name(data.op);
        if method.len() == 0 { return nil; }
        var receiver = data.left; var argument = data.right; var name = method; var negate = false;
        switch data.op {
            case ">": receiver = data.right; argument = data.left; name = "__lt__";
            case "<=": receiver = data.right; argument = data.left; name = "__lt__"; negate = true;
            case ">=": name = "__lt__"; negate = true;
            case "!=": name = "__eq__"; negate = true;
            default: {}
        }
        let label: String? = nil;
        var result_type = new_type; if negate { result_type = self.types.get_builtin("Bool") ?? new_type; }
        let call = self.specialize_method_call(receiver, HirMethodCallData { type_id: result_type, receiver, method_name: name,
            arguments: [(label, argument)], method_symbol: nil, is_static: false }, subst, result_type);
        if !negate { return call; }
        self.arena.add(HirForm.unary_op(HirUnaryOpData { type_id: result_type, op: "!", operand: call }))
    }
    def signature(func: HirFunctionData, subst: TypeSubstitution, result: TypeId? = nil) -> TypeId {
        let params = Vec<TypeId>.new(); for param in func.params { params.push(self.specialized_type(self.arena.type_of(param, self.types.error_type), subst)); }
        self.types.make_function(params, result ?? self.specialized_type(func.return_type, subst), func.is_async)
    }
    // `a == b` on optionals of `inner`: both nil, or both present with equal values.
    def optional_equality(left: HirId, right: HirId, op: String, inner: TypeId, bool_type: TypeId) -> HirId {
        let x = self.symbols.create_symbol("__lhs", SymbolKind.variable(), Namespace.value());
        let y = self.symbols.create_symbol("__rhs", SymbolKind.variable(), Namespace.value());
        let unused = self.symbols.create_symbol("__rhs", SymbolKind.variable(), Namespace.value());
        let x_ref = self.arena.add(HirForm.var_ref(HirVarData { type_id: inner, name: x.name, symbol_id: x.id }));
        let y_ref = self.arena.add(HirForm.var_ref(HirVarData { type_id: inner, name: y.name, symbol_id: y.id }));
        var values = self.arena.add(HirForm.binary_op(HirBinaryOpData { type_id: bool_type, left: x_ref, op: "==", right: y_ref }));
        if let info = self.types.get_type(inner) { switch info.data {
            case .struct_type | .enum_type:
                let label: String? = nil;
                values = self.specialize_method_call(x_ref, HirMethodCallData { type_id: bool_type, receiver: x_ref, method_name: "__eq__",
                    arguments: [(label, y_ref)], method_symbol: nil, is_static: false }, TypeSubstitution.new(), bool_type);
            case .optional(let nested): values = self.optional_equality(x_ref, y_ref, "==", nested, bool_type);
            default: {}
        } }
        let equal = self.arena.add(HirForm.literal(HirLiteralData { type_id: bool_type, value: HirValue.boolean(true), kind: "bool" }));
        let unequal = self.arena.add(HirForm.literal(HirLiteralData { type_id: bool_type, value: HirValue.boolean(false), kind: "bool" }));
        // The right operand appears in both branches of the left match; exactly one runs.
        let when_left = self.arena.add(HirForm.optional_match(HirOptionalMatchData { type_id: bool_type, scrutinee: right, inner_type: inner, some_binding: y.id, some_expr: values, none_expr: unequal }));
        let when_nil = self.arena.add(HirForm.optional_match(HirOptionalMatchData { type_id: bool_type, scrutinee: right, inner_type: inner, some_binding: unused.id, some_expr: unequal, none_expr: equal }));
        let result = self.arena.add(HirForm.optional_match(HirOptionalMatchData { type_id: bool_type, scrutinee: left, inner_type: inner, some_binding: x.id, some_expr: when_left, none_expr: when_nil }));
        if op.equals("!=") { return self.arena.add(HirForm.unary_op(HirUnaryOpData { type_id: bool_type, op: "!", operand: result })); }
        result
    }
    // Instantiates the generic extension method `sid` for `type`, as a call on it would.
    def require_method(type: TypeId, sid: SymbolId) -> Void {
        guard let original_id = self.originals[sid.id] else { return; }
        guard let original = self.func(original_id) else { return; }
        guard let info = self.types.get_type(type) else { return; }
        var arguments = Vec<TypeId>.new();
        switch info.data { case .struct_type(let d): arguments = d.type_args.to_vec(); case .enum_type(let d): arguments = d.type_args.to_vec(); default: return; }
        self.discover(type);
        let key = InstanceKey.new(sid, arguments); self.enqueue(0, key);
        self.special_symbol(key, mangle_name(original.name, key.type_args, self.types));
    }
    def specialize_call(id: HirId, data: HirCallData, subst: TypeSubstitution, new_type: TypeId) -> HirId {
        var callee = self.clone_node(data.callee, subst); let args = self.arguments(data.arguments, subst); var sid = data.callee_symbol;
        if let original_sid = sid {
            // Explicit type arguments seed the inference.
            var initial: Dict<String, TypeId>? = nil;
            if let explicit = self.arena.type_arguments[id.id] {
                let seeded = Dict<String, TypeId>.new();
                for pair in explicit.entries() { seeded[pair.key] = subst.apply(pair.value, self.types); }
                initial = seeded;
            }
            var type_args = self.infer_call(original_sid, self.inference_arguments(data.arguments, subst), subst.apply(data.type_id, self.types), initial);
            var invalid = false; for type in type_args { if self.types.is_error(type) { invalid = true; } }
            if type_args.len() > 0 && invalid {
                var name = "<generic call>"; if let id = self.originals[original_sid.id] { if let func = self.func(id) { name = func.name; } }
                self.errors.push("could not infer all type arguments for generic call to '" + name + "'"); type_args = Vec<TypeId>.new();
            }
            if type_args.len() > 0 {
                let key = InstanceKey.new(original_sid, type_args); self.enqueue(0, key);
                if let id = self.originals[original_sid.id] { if let func = self.func(id) {
                    let name = mangle_name(func.name, key.type_args, self.types); let new_sid = self.special_symbol(key, name); sid = new_sid;
                    if let node = self.arena.get(callee) { switch node.form { case .var_ref:
                        let signature = self.signature(func, self.substitution(original_sid, key.type_args));
                        callee = self.arena.add(HirForm.var_ref(HirVarData { type_id: signature, name, symbol_id: new_sid }));
                        default: {}
                    } }
                } }
            }
        }
        self.arena.add(HirForm.call(HirCallData { type_id: new_type, callee, arguments: args, callee_symbol: sid }))
    }
    def type_symbol(type: TypeId) -> SymbolId? {
        if let info = self.types.get_type(type) { switch info.data { case .struct_type(let d): return d.symbol_id; case .enum_type(let d): return d.symbol_id; case .optional: return self.symbols.get_builtin("?"); default: {} } }
        nil
    }
    def specialize_method_call(id: HirId, data: HirMethodCallData, subst: TypeSubstitution, new_type: TypeId) -> HirId {
        let receiver = self.clone_node(data.receiver, subst);
        // `value.hash()` on an optional, from generic code: the value's hash, or 0 for nil.
        if data.method_name.equals("hash") && !data.is_static && data.arguments.len() == 0 {
            if let inner = self.types.get_optional_inner(self.arena.type_of(receiver, self.types.error_type)) {
                let bound = self.symbols.create_symbol("__value", SymbolKind.variable(), Namespace.value());
                let value_ref = self.arena.add(HirForm.var_ref(HirVarData { type_id: inner, name: bound.name, symbol_id: bound.id }));
                let some = self.specialize_method_call(value_ref, HirMethodCallData { type_id: new_type, receiver: value_ref, method_name: "hash",
                    arguments: Vec<(String?, HirId)>.new(), method_symbol: nil, is_static: false }, TypeSubstitution.new(), new_type);
                let none = self.arena.add(HirForm.literal(HirLiteralData { type_id: new_type, value: HirValue.integer("0"), kind: "int" }));
                return self.arena.add(HirForm.optional_match(HirOptionalMatchData { type_id: new_type, scrutinee: receiver, inner_type: inner, some_binding: bound.id, some_expr: some, none_expr: none }));
            }
        } let args = self.arguments(data.arguments, subst); var method_symbol = data.method_symbol;
        var generic_symbol = data.method_symbol;
        if let known = data.method_symbol {} else {
            // A protocol requirement called on a type parameter now has a concrete receiver.
            if let tsid = self.type_symbol(subst.apply(self.arena.type_of(data.receiver, self.types.error_type), self.types)) { generic_symbol = self.generic_methods[f"{tsid.id}:{data.method_name}"]; }
        }
        if let sid = generic_symbol { if let owner = self.method_owners[sid.id] { if let original_id = self.originals[sid.id] { if let original = self.func(original_id) {
            let initial = Dict<String, TypeId>.with_capacity(16, 1); var owner_args = Vec<TypeId>.new();
            if let info = self.types.get_type(subst.apply(self.arena.type_of(data.receiver, self.types.error_type), self.types)) { switch info.data { case .struct_type(let d): owner_args = d.type_args.to_vec(); case .enum_type(let d): owner_args = d.type_args.to_vec(); case .optional(let inner): owner_args = [inner]; default: {} } }
            let owner_names = self.generic_names(owner); for i in 0..<owner_names.len() { if i < owner_args.len() { initial[owner_names[i]] = owner_args[i]; } }
            // Explicit type arguments, `value.method<T>(...)`, seed the method's own parameters.
            if let explicit = self.arena.type_arguments[id.id] { for pair in explicit.entries() { initial[pair.key] = subst.apply(pair.value, self.types); } }
            let type_args = self.infer_call(sid, self.inference_arguments(data.arguments, subst), subst.apply(data.type_id, self.types), initial);
            for type in type_args { if self.types.is_error(type) || self.types.has_type_variables(type) { self.errors.push("could not infer type arguments for generic method '" + original.name + "'"); return id; } }
            let key = InstanceKey.new(sid, type_args); self.enqueue(0, key); let name = mangle_name(original.name + f"$method{sid.id}", key.type_args, self.types); let new_sid = self.special_symbol(key, name);
            let signature = self.signature(original, self.substitution(sid, key.type_args), new_type);
            let callee = self.arena.add(HirForm.var_ref(HirVarData { type_id: signature, name, symbol_id: new_sid }));
            let arguments = Vec<(String?, HirId)>.new(); if !data.is_static { let label: String? = nil; arguments.push((label, receiver)); } for arg in args { arguments.push(arg); }
            return self.arena.add(HirForm.call(HirCallData { type_id: new_type, callee, arguments, callee_symbol: new_sid }));
        } } } }
        let receiver_type = self.arena.type_of(receiver, self.types.error_type); self.discover(receiver_type);
        if let sid = method_symbol { if let original_id = self.originals[sid.id] { if let original = self.func(original_id) { if let info = self.types.get_type(receiver_type) { switch info.data { case .struct_type(let d):
            var variables = false; for arg in d.type_args { if self.types.has_type_variables(arg) { variables = true; } }
            if d.type_args.len() > 0 && !variables { let key = InstanceKey.new(sid, d.type_args.to_vec()); self.enqueue(0, key); method_symbol = self.special_symbol(key, mangle_name(original.name, key.type_args, self.types)); }
            default: {}
        } } } } }
        self.arena.add(HirForm.method_call(HirMethodCallData { type_id: new_type, receiver, method_name: data.method_name, arguments: args, method_symbol, is_static: data.is_static }))
    }
    def infer_call(sid: SymbolId, arguments: Vec<TypeId>, return_type: TypeId, initial: Dict<String, TypeId>? = nil) -> Vec<TypeId> {
        let names = self.generic_names(sid); let out = Vec<TypeId>.new(); if names.len() == 0 { return out; }
        guard let symbol = self.symbols.get_symbol(sid) else { return out; }
        guard let ref = symbol.decl_node else { return out; }
        guard let node = self.input.ast.get(ref) else { return out; }
        switch node.form { case .func_decl(let decl):
            let params = Dict<String, Bool>.with_capacity(16, 1); let variables = Dict<String, TypeId>.with_capacity(16, 1);
            for name in names { params[name] = true; variables[name] = self.types.make_type_variable(name); }
            let inferred = initial ?? Dict<String, TypeId>.with_capacity(16, 1);
            if let syntax = decl.return_type { infer_resolved_type_arguments(self.types, self.resolver.resolve(syntax, variables), return_type, params, inferred); }
            for i in 0..<arguments.len() { if i >= decl.params.len() { break; } if let param = self.input.ast.get(decl.params[i]) { switch param.form { case .param(let d): if let syntax = d.type_annotation { infer_resolved_type_arguments(self.types, self.resolver.resolve(syntax, variables), arguments[i], params, inferred); } default: {} } } }
            for name in names { out.push(inferred[name] ?? self.types.error_type); }
            default: {}
        }
        out
    }
    def discover(type: TypeId) -> Void {
        if let info = self.types.get_type(type) { switch info.data {
            case .struct_type(let data):
                if let sid = data.symbol_id {
                    var variables = false; for arg in data.type_args { if self.types.has_type_variables(arg) { variables = true; } }
                    if self.struct_originals.contains(sid.id) { if self.decl_params(sid).len() == 0 || (data.type_args.len() > 0 && !variables) { self.enqueue(1, InstanceKey.new(sid, data.type_args.to_vec())); } }
                    for arg in data.type_args { self.discover(arg); }
                } else { if let fields = data.anon_fields { for field in fields { self.discover(field.type_id); } } }
            case .enum_type(let data):
                var variables = false; for arg in data.type_args { if self.types.has_type_variables(arg) { variables = true; } }
                if self.enum_originals.contains(data.symbol_id.id) { if self.decl_params(data.symbol_id).len() == 0 || (data.type_args.len() > 0 && !variables) { self.enqueue(2, InstanceKey.new(data.symbol_id, data.type_args.to_vec())); } }
                for arg in data.type_args { self.discover(arg); }
            case .optional(let inner): self.discover(inner);
            default: {}
        } }
    }
    def build_result() -> MonomorphizationResult {
        let items = Vec<HirId>.new(); let extension_methods = Dict<i32, Bool>.with_capacity(16, 0);
        for id in self.items() { if let node = self.arena.get(id) { switch node.form { case .extension(let d): for method in d.methods { if let func = self.func(method) { if !self.method_owners.contains(func.symbol_id.id) { extension_methods[func.symbol_id.id] = true; } } } default: {} } } }
        for id in self.items() { if let node = self.arena.get(id) { switch node.form {
            case .extern_func, .protocol: items.push(id);
            case .extension(let data):
                let methods = Vec<HirId>.new(); for method in data.methods { if let func = self.func(method) {
                    if self.method_owners.contains(func.symbol_id.id) { continue; }
                    if let instance = self.functions[InstanceKey.new(func.symbol_id, Vec<TypeId>.new()).key()] { methods.push(instance.specialized); } else { methods.push(method); }
                } }
                items.push(self.arena.add(HirForm.extension(HirExtensionData { extended_type: self.nested(data.extended_type), methods })));
            default: {}
        } } }
        for key in self.function_order { if let instance = self.functions[key] { if !extension_methods.contains(instance.key.symbol_id.id) { items.push(instance.specialized); } } }
        for key in self.struct_order { if let instance = self.structs[key] { items.push(instance.specialized); } }
        for key in self.enum_order { if let instance = self.enums[key] { items.push(instance.specialized); } }
        MonomorphizationResult { ast: self.input.ast, arena: self.arena, program: self.arena.add(HirForm.program(HirProgramData { items })), type_table: self.types, symbol_table: self.symbols,
            function_instances: self.functions, struct_instances: self.structs, enum_instances: self.enums, errors: self.errors }
    }
}
