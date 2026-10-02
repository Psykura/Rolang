// Member lookup, extension visibility and instantiated member types.
pub import "members.rl"
pub import "type_resolver.rl"

pub def extension_methods_clash(a: MethodInfo, b: MethodInfo) -> Bool {
    if a.visibility.equals("pub") || b.visibility.equals("pub") { return true; }
    if let left = a.source_module {
        if let right = b.source_module { return left.equals(right); }
    }
    true
}

pub struct MemberResolver {
    pub let arena: AstArena;
    pub let type_table: TypeTable;
    pub let symbol_table: SymbolTable;
    let type_resolver: TypeResolver;
    let cache: Dict<i32, TypeMembers>;
    let extension_methods: Dict<i32, Vec<MethodInfo>>;
    var current_source_module: String?;
    pub static def new(arena: AstArena, type_table: TypeTable, symbol_table: SymbolTable) -> MemberResolver {
        MemberResolver {
            arena, type_table, symbol_table,
            type_resolver: TypeResolver.new(arena, type_table, symbol_table, nil, nil, nil, true),
            cache: Dict<i32, TypeMembers>.with_capacity(16, 0),
            extension_methods: Dict<i32, Vec<MethodInfo>>.with_capacity(16, 0), current_source_module: nil
        }
    }
    pub def set_current_source_module(module: String?) -> Void { self.current_source_module = module; }
    pub def get_current_source_module() -> String? { self.current_source_module }
    pub def get_members(type_id: TypeId) -> TypeMembers {
        if let members = self.cache[type_id.id] { return members; }
        let members = self.resolve_members(type_id);
        self.cache[type_id.id] = members;
        members
    }
    pub def get_field(type_id: TypeId, name: String) -> FieldInfo? { self.get_members(type_id).fields[name] }
    pub def get_method(type_id: TypeId, name: String, static: Bool? = false) -> MethodInfo? {
        if let method = self.get_members(type_id).methods[name] {
            if let flag = static { if method.is_static == flag { return method; } }
            else { return method; }
        }
        var type_symbol: SymbolId? = nil;
        if let info = self.type_table.get_type(type_id) {
            switch info.data {
                case .struct_type(let data): type_symbol = data.symbol_id;
                case .enum_type(let data): type_symbol = data.symbol_id;
                case .primitive(let primitive): type_symbol = self.symbol_table.get_builtin(primitive.spelling());
                default: {}
            }
        }
        if let symbol = type_symbol {
            if let methods = self.extension_methods[symbol.id] {
                for method in methods {
                    if !method.name.equals(name) { continue; }
                    if let flag = static { if method.is_static != flag { continue; } }
                    if let author = method.source_module {
                        if !method.visibility.equals("pub") {
                            if let caller = self.current_source_module { if !author.equals(caller) { continue; } }
                        }
                    }
                    return method;
                }
            }
        }
        var instance_allowed = true;
        if let flag = static { instance_allowed = !flag; }
        if name.equals("clone") && instance_allowed && self.type_table.is_heap_type(type_id) {
            return MethodInfo {
                name, symbol_id: SymbolId { id: -1 },
                signature: self.type_table.make_function(Vec<TypeId>.new(), type_id),
                is_static: false, visibility: "pub", source_module: nil
            };
        }
        nil
    }
    pub def register_extension(type_symbol: SymbolId, methods: Vec<MethodInfo>) -> Vec<(MethodInfo, MethodInfo)> {
        let bucket = self.extension_methods[type_symbol.id] ?? Vec<MethodInfo>.new();
        let conflicts = Vec<(MethodInfo, MethodInfo)>.new();
        for method in methods {
            var registered = false;
            for previous in bucket { if previous.symbol_id == method.symbol_id { registered = true; break; } }
            if registered { continue; }
            for previous in bucket {
                if previous.name.equals(method.name) && extension_methods_clash(previous, method) {
                    conflicts.push((previous, method));
                }
            }
            bucket.push(method);
        }
        self.extension_methods[type_symbol.id] = bucket;
        conflicts
    }
    def resolve_members(type_id: TypeId) -> TypeMembers {
        guard let info = self.type_table.get_type(type_id) else { return TypeMembers.new(); }
        switch info.data {
            case .struct_type(let data):
                if let symbol = data.symbol_id { return self.resolve_named_members(symbol, data.type_args, false); }
                let members = TypeMembers.new();
                if let fields = data.anon_fields {
                    var index = 0;
                    for field in fields {
                        let field_type = self.monomorphize_nested(field.type_id);
                        members.fields[field.name] = FieldInfo {
                            name: field.name, type_id: field_type, is_mutable: true, index,
                            visibility: "internal", source_module: nil
                        };
                        var numeric = field.name.len() > 0;
                        for position in 0..<(field.name.len() as i32) {
                            let byte = field.name.byte_at(position);
                            if byte < 48 || byte > 57 { numeric = false; }
                        }
                        if !numeric {
                            let name = index.to_string();
                            members.fields[name] = FieldInfo {
                                name, type_id: field_type, is_mutable: true, index,
                                visibility: "internal", source_module: nil
                            };
                        }
                        index += 1;
                    }
                }
                return members;
            case .enum_type(let data): return self.resolve_named_members(data.symbol_id, data.type_args, true);
            case .optional(let inner):
                let members = TypeMembers.new();
                if let bool_type = self.type_table.get_builtin("Bool") {
                    let signature = self.type_table.make_function(Vec<TypeId>.new(), bool_type);
                    for name in ["is_some", "is_none"] {
                        members.methods[name] = MethodInfo {
                            name, symbol_id: SymbolId { id: -1 }, signature,
                            is_static: false, visibility: "pub", source_module: nil
                        };
                    }
                }
                let name = "unwrap_or";
                members.methods[name] = MethodInfo {
                    name, symbol_id: SymbolId { id: -1 }, signature: self.type_table.make_function([inner], inner),
                    is_static: false, visibility: "pub", source_module: nil
                };
                return members;
            default: {}
        }
        TypeMembers.new()
    }
    def effective_args(symbol: SymbolId, args: FrozenVec<TypeId>) -> FrozenVec<TypeId> {
        if args.len() == 0 {
            if let origin = self.symbol_table.specialization_origin[symbol.id] { return origin.type_args; }
        }
        args
    }
    def resolve_named_members(symbol: SymbolId, args: FrozenVec<TypeId>, enum_type: Bool) -> TypeMembers {
        let effective = self.effective_args(symbol, args);
        if let cached = self.type_table.get_type_members(symbol) {
            let subst = Dict<String, TypeId>.with_capacity(16, 1);
            var index = 0;
            for name in cached.generic_param_names {
                if index < effective.len() { subst[name] = effective.get(index); }
                index += 1;
            }
            let members = TypeMembers.new();
            if !enum_type {
                for pair in cached.fields.entries() {
                    let field = pair.value;
                    members.fields[pair.key] = FieldInfo {
                        name: field.name, type_id: self.monomorphize_nested(self.substitute_member_type(field.type_id, subst)),
                        is_mutable: field.is_mutable, index: field.index,
                        visibility: field.visibility, source_module: field.source_module
                    };
                }
            }
            for pair in cached.methods.entries() {
                let method = pair.value;
                members.methods[pair.key] = MethodInfo {
                    name: method.name, symbol_id: method.symbol_id,
                    signature: self.substitute_member_type(method.signature, subst),
                    is_static: !enum_type && method.is_static, visibility: "pub", source_module: nil
                };
            }
            return members;
        }
        return self.resolve_members_from_ast(symbol, effective, enum_type);
    }
    def resolve_members_from_ast(symbol: SymbolId, args: FrozenVec<TypeId>, enum_type: Bool) -> TypeMembers {
        let members = TypeMembers.new();
        guard let info = self.symbol_table.get_symbol(symbol) else { return members; }
        guard let id = info.decl_node else { return members; }
        guard let node = self.arena.get(id) else { return members; }
        let generics = Vec<NodeId>.new();
        let items = Vec<NodeId>.new();
        switch node.form {
            case .struct_decl(let data):
                if enum_type { return members; }
                for param in data.generic_params { generics.push(param); }
                for member in data.members { items.push(member); }
            case .enum_decl(let data):
                if !enum_type { return members; }
                for param in data.generic_params { generics.push(param); }
                for member in data.members { items.push(member); }
            default: return members;
        }
        let subst = Dict<String, TypeId>.with_capacity(16, 1);
        for index in 0..<generics.len() {
            if index >= args.len() { break; }
            if let param = self.arena.get(generics[index]) {
                switch param.form { case .generic_param(let data): subst[data.name] = args.get(index); default: {} }
            }
        }
        var field_index = 0;
        for member in items {
            guard let member_node = self.arena.get(member) else { continue; }
            switch member_node.form {
                case .property_decl(let data):
                    if enum_type { continue; }
                    members.fields[data.name] = FieldInfo {
                        name: data.name, type_id: self.monomorphize_nested(self.type_resolver.resolve(data.type_annotation, subst)),
                        is_mutable: data.is_mutable, index: field_index, visibility: data.visibility,
                        source_module: self.arena.source_module(id)
                    };
                    field_index += 1;
                case .func_decl(let data):
                    let signature = self.resolve_method_type(data, subst);
                    if let method_symbol = self.symbol_table.get_symbol_by_node(member) {
                        members.methods[data.name] = MethodInfo {
                            name: data.name, symbol_id: method_symbol, signature,
                            is_static: data.is_static, visibility: "pub", source_module: nil
                        };
                    }
                default: {}
            }
        }
        members
    }
    pub def resolve_method_type(data: FuncDeclAst, subst: Dict<String, TypeId>) -> TypeId {
        let params = Vec<TypeId>.new();
        for id in data.params {
            if let node = self.arena.get(id) {
                switch node.form { case .param(let param): params.push(self.type_resolver.resolve(param.type_annotation, subst)); default: {} }
            }
        }
        var result = self.type_table.void_type;
        if let returned = data.return_type { result = self.type_resolver.resolve(returned, subst); }
        self.type_table.make_function(params, result, data.is_async)
    }
    pub def substitute_member_type(type_id: TypeId, subst: Dict<String, TypeId>) -> TypeId {
        if subst.len() == 0 { return type_id; }
        guard let info = self.type_table.get_type(type_id) else { return type_id; }
        switch info.data {
            case .type_variable(let data): return subst[data.name] ?? (self.type_table.project(data.name, subst) ?? type_id);
            case .struct_type(let data):
                if let symbol = data.symbol_id {
                    let args = Vec<TypeId>.new();
                    for arg in data.type_args { args.push(self.substitute_member_type(arg, subst)); }
                    return self.type_table.make_struct(symbol, args);
                }
                let fields = Vec<(String?, TypeId)>.new();
                if let values = data.anon_fields {
                    for field in values {
                        let name: String? = field.name;
                        fields.push((name, self.substitute_member_type(field.type_id, subst)));
                    }
                }
                return self.type_table.make_tuple(fields);
            case .enum_type(let data):
                let args = Vec<TypeId>.new();
                for arg in data.type_args { args.push(self.substitute_member_type(arg, subst)); }
                return self.type_table.make_enum(data.symbol_id, args);
            case .function(let data):
                let params = Vec<TypeId>.new();
                for param in data.params { params.push(self.substitute_member_type(param, subst)); }
                return self.type_table.make_function(params, self.substitute_member_type(data.return_type, subst), data.is_async);
            case .optional(let inner): return self.type_table.make_optional(self.substitute_member_type(inner, subst));
            default: {}
        }
        type_id
    }
    pub def monomorphize_nested(type_id: TypeId) -> TypeId {
        guard let info = self.type_table.get_type(type_id) else { return type_id; }
        switch info.data {
            case .struct_type(let data):
                if let symbol = data.symbol_id {
                    let args = Vec<TypeId>.new();
                    for arg in data.type_args { args.push(self.monomorphize_nested(arg)); }
                    if args.len() > 0 {
                        if let specialized = self.symbol_table.find_specialization(symbol, args) {
                            return self.type_table.make_struct(specialized);
                        }
                    }
                    return self.type_table.make_struct(symbol, args);
                }
                let fields = Vec<(String?, TypeId)>.new();
                if let values = data.anon_fields {
                    for field in values {
                        let name: String? = field.name;
                        fields.push((name, self.monomorphize_nested(field.type_id)));
                    }
                }
                return self.type_table.make_tuple(fields);
            case .enum_type(let data):
                let args = Vec<TypeId>.new();
                for arg in data.type_args { args.push(self.monomorphize_nested(arg)); }
                if args.len() > 0 {
                    if let specialized = self.symbol_table.find_specialization(data.symbol_id, args) {
                        return self.type_table.make_enum(specialized);
                    }
                }
                return self.type_table.make_enum(data.symbol_id, args);
            case .optional(let inner): return self.type_table.make_optional(self.monomorphize_nested(inner));
            case .function(let data):
                let params = Vec<TypeId>.new();
                for param in data.params { params.push(self.monomorphize_nested(param)); }
                return self.type_table.make_function(params, self.monomorphize_nested(data.return_type), data.is_async);
            default: {}
        }
        type_id
    }
}
