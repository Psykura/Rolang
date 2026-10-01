// Declaration checking passes.
pub import "checker_state.rl"
import std.collections
pub struct DeclChecker {
    pub let state: CheckerState;
    pub static def new(state: CheckerState) -> DeclChecker { DeclChecker { state } }
    pub def run(program: NodeId) -> Void {
        if let node = self.state.arena.get(program) {
            switch node.form { case .program(let data):
                for item in data.items { self.collect_type(item); }
                self.register_imports();
                for item in data.items { self.check_item(item); }
                default: {}
            }
        }
    }
    def signature(params: Vec<NodeId>, return_type: NodeId?, async: Bool) -> TypeId {
        let types = Vec<TypeId>.new();
        for id in params { if let param = self.state.param(id) { types.push(self.state.resolve_type(param.type_annotation)); } }
        self.state.type_table.make_function(types, self.return_type(return_type), async)
    }
    def return_type(id: NodeId?) -> TypeId {
        if let ref = id { return self.state.resolve_type(ref); }
        self.state.type_table.void_type
    }
    def collect_type(id: NodeId) -> Void {
        guard let symbol = self.state.node_symbols[id.id] else { return; }
        guard let node = self.state.arena.get(id) else { return; }
        switch node.form {
            case .struct_decl: self.state.type_table.make_struct(symbol);
            case .enum_decl: self.state.type_table.make_enum(symbol);
            case .protocol_decl(let data):
                let funcs = Vec<FuncRequirement>.new(); let props = Vec<PropRequirement>.new();
                for member in data.members {
                    if let child = self.state.arena.get(member) {
                        switch child.form {
                            case .protocol_func_req(let req):
                                let params = Vec<TypeId>.new();
                                for p in req.params { if let param = self.state.param(p) { params.push(self.state.resolve_type(param.type_annotation)); } }
                                funcs.push(FuncRequirement { name: req.name, params: FrozenVec<TypeId>.new(params), return_type: self.return_type(req.return_type), is_async: req.is_async, is_static: false });
                            case .protocol_prop_req(let req): props.push(PropRequirement { name: req.name, type_id: self.state.resolve_type(req.type_annotation), has_getter: req.has_getter, has_setter: req.has_setter });
                            default: {}
                        }
                    }
                }
                self.state.type_table.make_protocol(symbol, funcs, props);
            default: {}
        }
    }
    def register_imports() -> Void {
        for entry in self.state.resolution.imported_symbols.entries() {
            if entry.key.contains(".") { continue; }
            if let sym = self.state.symbol_table.get_symbol(entry.value) {
                if let decl = sym.decl_node {
                    switch sym.kind {
                        case .struct_type: self.state.type_table.make_struct(sym.id);
                        case .enum_type: self.state.type_table.make_enum(sym.id);
                        case .protocol: self.state.type_table.get_protocol_type(sym.id);
                        default: {}
                    }
                }
            }
        }
        for entry in self.state.resolution.imported_extension_methods.entries() {
            var type_symbol: SymbolId? = nil;
            for sym in self.state.symbol_table.symbols.values() {
                if sym.name.equals(entry.key) {
                    switch sym.kind { case .struct_type | .enum_type | .builtin_type: type_symbol = sym.id; default: {} }
                    if let found = type_symbol { break; }
                }
            }
            if let target = type_symbol {
                let methods = Vec<MethodInfo>.new();
                for method in entry.value {
                    if let symbol = self.state.symbol_table.get_symbol(method.symbol_id) {
                        if let data = self.state.function(symbol.decl_node) {
                            methods.push(MethodInfo { name: method.name, symbol_id: symbol.id, signature: self.signature(data.params, data.return_type, data.is_async), is_static: data.is_static, visibility: "pub", source_module: nil });
                        }
                    }
                }
                if methods.len() > 0 { self.conflicts(entry.key, self.state.member_resolver.register_extension(target, methods), nil); }
            }
        }
    }
    def check_item(id: NodeId) -> Void {
        guard let node = self.state.arena.get(id) else { return; }
        let previous = self.state.member_resolver.get_current_source_module();
        self.state.member_resolver.set_current_source_module(self.state.arena.source_module(id));
        defer { self.state.member_resolver.set_current_source_module(previous); }
        switch node.form {
            case .func_decl(let data):
                if data.is_static { self.state.error(TypeErrorKind.invalid_operation(), "'static' is only valid on methods inside a type or extension", id); }
                self.check_function(id, data);
                if data.visibility.equals("pub") {
                    let seen = Dict<i32, Bool>.with_capacity(16, 0);
                    for param in data.params { if let p = self.state.param(param) { self.privacy(id, data.name, "function", self.state.resolve_type(p.type_annotation), "parameter", seen); } }
                    self.privacy(id, data.name, "function", self.return_type(data.return_type), "return type", seen);
                }
            case .extern_func_decl(let data):
                for param in data.params { if let p = self.state.param(param) { self.state.resolve_type(p.type_annotation); } }
                if let ret = data.return_type { self.state.resolve_type(ret); }
            case .struct_decl(let data): self.check_type(id, data.generic_params, data.members, false);
            case .enum_decl(let data): self.check_type(id, data.generic_params, data.members, true);
            case .type_alias_decl(let data):
                let type = self.state.resolve_type(data.aliased_type);
                if data.visibility.equals("pub") { self.privacy(id, data.name, "type alias", type, "aliased type", Dict<i32, Bool>.with_capacity(16, 0)); }
            case .extension_decl(let data): self.check_extension(id, data);
            default: {}
        }
    }
    def check_function(id: NodeId, data: FuncDeclAst) -> Void {
        if !data.is_static {
            if let type = self.state.current_self_type { if let symbol = self.state.node_symbols[id.id] { if let bound = self.state.resolution.self_symbols[symbol.id] { self.state.type_env[bound.id] = type; } } }
        }
        for param in data.params {
            if let p = self.state.param(param) {
                let type = self.state.resolve_type(p.type_annotation);
                if let symbol = self.state.node_symbols[param.id] { self.state.type_env[symbol.id] = type; }
                if let value = p.default_value { self.state.check_assignable(self.state.infer_with_expected(value, type), type, f"default value for parameter '{p.internal_name}'", param); }
            }
        }
        let ret = self.return_type(data.return_type);
        if data.throws {
            var is_enum = false;
            if let info = self.state.type_table.get_type(ret) { switch info.data { case .enum_type: is_enum = true; default: {} } }
            if !is_enum { self.state.error(TypeErrorKind.invalid_operation(), f"function '{data.name}' is declared 'throws' but does not return a Result-shaped type; declare a Result<T, E> return type or remove 'throws'"); }
        }
        let old_return = self.state.current_function_return; let old_async = self.state.in_async_function;
        self.state.current_function_return = ret; self.state.in_async_function = data.is_async;
        defer { self.state.current_function_return = old_return; self.state.in_async_function = old_async; }
        if let body = data.body {
            self.state.check_block(body);
            if ret != self.state.type_table.void_type && !self.state.definitely_returns(self.state.block_statements(body)) { self.state.error(TypeErrorKind.type_mismatch(), f"function '{data.name}' must return a value of type {self.state.type_table.format_type(ret)} on all paths", id); }
        }
    }
    def check_type(id: NodeId, generics: Vec<NodeId>, members: Vec<NodeId>, enum: Bool) -> Void {
        let symbol = self.state.node_symbols[id.id];
        let old = self.state.current_self_type; self.state.current_self_type = nil;
        if let sid = symbol {
            let args = self.state.generic_inference.make_generic_param_type_args(generics);
            if enum { self.state.current_self_type = self.state.type_table.make_enum(sid, args); }
            else { self.state.current_self_type = self.state.type_table.make_struct(sid, args); }
        }
        defer { self.state.current_self_type = old; }
        for member in members {
            if let node = self.state.arena.get(member) {
                switch node.form {
                    case .property_decl(let prop):
                        if !enum {
                            if let ann = prop.type_annotation { let type = self.state.resolve_type(ann); if let sid = self.state.node_symbols[member.id] { self.state.type_env[sid.id] = type; } }
                            if let init = prop.initializer { let type = self.state.infer_expr(init); if let ann = prop.type_annotation { self.state.check_assignable(type, self.state.resolve_type(ann), "property initializer"); } }
                        }
                    case .enum_case_decl(let group):
                        for case_id in group.cases { if let child = self.state.arena.get(case_id) { switch child.form { case .enum_case_def(let data): for payload in data.payload { self.state.resolve_type(payload.1); } default: {} } } }
                    case .func_decl(let func): self.check_function(member, func);
                    default: {}
                }
            }
        }
        if let sid = symbol {
            let cache = TypeMembers.new(); let names = Vec<String>.new(); for p in generics { names.push(self.state.generic_name(p)); }
            cache.generic_param_names = FrozenVec<String>.new(names);
            for index in 0..<members.len() {
                let member = members[index];
                if let node = self.state.arena.get(member) {
                    switch node.form {
                        case .property_decl(let prop): if !enum { cache.fields[prop.name] = FieldInfo { name: prop.name, type_id: self.state.resolve_type(prop.type_annotation), is_mutable: prop.is_mutable, index, visibility: prop.visibility, source_module: self.state.arena.source_module(id) }; }
                        case .func_decl(let func): if let method = self.state.node_symbols[member.id] { cache.methods[func.name] = MethodInfo { name: func.name, symbol_id: method, signature: self.signature(func.params, func.return_type, func.is_async), is_static: func.is_static, visibility: "pub", source_module: nil }; }
                        default: {}
                    }
                }
            }
            self.state.type_table.set_type_members(sid, cache);
        }
    }
    def named_name(id: NodeId?) -> String {
        if let ref = id { if let node = self.state.arena.get(ref) { switch node.form { case .named_type(let data): return data.name; case .builtin_type(let data): return data.name; default: {} } } }
        "?"
    }
    def check_extension(id: NodeId, data: ExtensionDeclAst) -> Void {
        let type = self.state.resolve_type(data.extended_type);
        var symbol: SymbolId? = nil;
        if let ref = data.extended_type { symbol = self.state.node_symbols[ref.id]; }
        if let sid = symbol {} else { if let info = self.state.type_table.get_type(type) { switch info.data { case .primitive: symbol = self.state.symbol_table.get_builtin(self.named_name(data.extended_type)); default: {} } } }
        let old = self.state.current_self_type; self.state.current_self_type = type;
        let methods = Vec<MethodInfo>.new();
        for member in data.members {
            if let node = self.state.arena.get(member) {
                switch node.form {
                    case .func_decl(let func):
                        self.check_function(member, func);
                        if let sid = self.state.node_symbols[member.id] { methods.push(MethodInfo { name: func.name, symbol_id: sid, signature: self.signature(func.params, func.return_type, func.is_async), is_static: func.is_static, visibility: data.visibility, source_module: self.state.arena.source_module(id) }); }
                    case .property_decl(let prop): if let ann = prop.type_annotation { self.state.resolve_type(ann); }
                    default: {}
                }
            }
        }
        self.state.current_self_type = old;
        if let sid = symbol { if methods.len() > 0 { self.conflicts(self.named_name(data.extended_type), self.state.member_resolver.register_extension(sid, methods), id); } }
        for conformance in data.conformances {
            let protocol = self.state.resolve_type(conformance);
            if self.state.type_table.is_error(protocol) { continue; }
            let name = self.named_name(conformance);
            if !self.state.type_table.is_protocol(protocol) { self.state.error(TypeErrorKind.not_a_protocol(), f"'{name}' is not a protocol; only protocols can appear in an extension's conformance clause"); continue; }
            if let sid = self.state.node_symbols[id.id] { self.state.conformance_checker.register_extension(type, protocol, sid); }
            let result = self.state.conformance_checker.check_conformance(type, protocol);
            if !result.conforms {
                let parts = Vec<String>.new();
                if result.missing_requirements.len() > 0 { parts.push("missing requirements: " + join_strings(result.missing_requirements, ", ")); }
                if result.errors.len() > 0 { parts.push(result.errors[0]); }
                var detail = ""; if parts.len() > 0 { detail = "; " + join_strings(parts, "; "); }
                self.state.error(TypeErrorKind.protocol_not_satisfied(), f"Type {self.state.type_table.format_type(type)} does not conform to {name}{detail}");
            }
        }
    }
    def conflicts(name: String, conflicts: Vec<(MethodInfo, MethodInfo)>, id: NodeId?) -> Void {
        let seen = Dict<String, Bool>.with_capacity(16, 1);
        for pair in conflicts {
            let key = f"{pair.0.symbol_id.id}:{pair.1.symbol_id.id}";
            if seen.contains(key) { continue; } seen[key] = true;
            self.state.error(TypeErrorKind.duplicate_member(), f"Extension method '{pair.1.name}' is already defined on type '{name}' (conflicting declarations are visible to the same module)", id);
        }
    }
    def privacy(id: NodeId, name: String, kind: String, type: TypeId, role: String, seen: Dict<i32, Bool>) -> Void {
        if seen.contains(type.id) { return; } seen[type.id] = true;
        guard let info = self.state.type_table.get_type(type) else { return; }
        var symbol: SymbolId? = nil;
        switch info.data { case .struct_type(let data): symbol = data.symbol_id; case .enum_type(let data): symbol = data.symbol_id; case .protocol(let data): symbol = data.symbol_id; default: {} }
        if let sid = symbol { if let sym = self.state.symbol_table.get_symbol(sid) {
            switch sym.kind { case .generic_param | .builtin_type: {} default: if !sym.visibility.equals("pub") { self.state.error(TypeErrorKind.invalid_operation(), f"public {kind} '{name}' exposes non-public type '{sym.name}' in its {role}", id); } }
        } }
        switch info.data {
            case .struct_type(let data):
                for arg in data.type_args { self.privacy(id, name, kind, arg, role, seen); }
                if let fields = data.anon_fields { for field in fields { self.privacy(id, name, kind, field.type_id, role, seen); } }
            case .enum_type(let data): for arg in data.type_args { self.privacy(id, name, kind, arg, role, seen); }
            case .existential(let data): self.privacy(id, name, kind, data.protocol_id, role, seen);
            case .function(let data): for param in data.params { self.privacy(id, name, kind, param, role, seen); } self.privacy(id, name, kind, data.return_type, role, seen);
            case .closure(let data): for param in data.params { self.privacy(id, name, kind, param, role, seen); } self.privacy(id, name, kind, data.return_type, role, seen);
            case .optional(let inner): self.privacy(id, name, kind, inner, role, seen);
            default: {}
        }
    }
}
