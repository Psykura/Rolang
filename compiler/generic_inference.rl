// Canonical unification and bidirectional generic call inference.
pub import "conformance.rl"
pub import "checker_core.rl"
import "member_resolver.rl"

pub def infer_resolved_type_arguments(table: TypeTable, pattern: TypeId, concrete: TypeId,
                                      names: Dict<String, Bool>, inferred: Dict<String, TypeId>) -> Void {
    guard let template = table.get_type(pattern) else { return; }
    guard let actual = table.get_type(concrete) else { return; }
    if table.is_error(concrete) { return; }
    switch template.data {
        case .type_variable(let left):
            if names.contains(left.name) && !inferred.contains(left.name) { inferred[left.name] = concrete; }
        case .optional(let inner):
            infer_resolved_type_arguments(table, inner, table.get_optional_inner(concrete) ?? concrete, names, inferred);
        case .function(let left):
            switch actual.data {
                case .function(let right):
                    var index = 0;
                    while index < left.params.len() && index < right.params.len() {
                        infer_resolved_type_arguments(table, left.params.get(index), right.params.get(index), names, inferred); index += 1;
                    }
                    infer_resolved_type_arguments(table, left.return_type, right.return_type, names, inferred);
                default: {}
            }
        case .struct_type(let left):
            switch actual.data {
                case .struct_type(let right):
                    if let symbol = left.symbol_id {
                        if let other = right.symbol_id {
                            if symbol == other { infer_type_pairs(table, left.type_args, right.type_args, names, inferred); }
                        }
                    } else {
                        if let symbol = right.symbol_id { return; }
                        if let fields = left.anon_fields {
                            if let other = right.anon_fields {
                                var index = 0;
                                while index < fields.len() && index < other.len() {
                                    infer_resolved_type_arguments(table, fields.get(index).type_id, other.get(index).type_id, names, inferred); index += 1;
                                }
                            }
                        }
                    }
                default: {}
            }
        case .enum_type(let left):
            switch actual.data {
                case .enum_type(let right): if left.symbol_id == right.symbol_id { infer_type_pairs(table, left.type_args, right.type_args, names, inferred); }
                default: {}
            }
        default: {}
    }
}
def infer_type_pairs(table: TypeTable, left: FrozenVec<TypeId>, right: FrozenVec<TypeId>,
                     names: Dict<String, Bool>, inferred: Dict<String, TypeId>) -> Void {
    var index = 0;
    while index < left.len() && index < right.len() {
        infer_resolved_type_arguments(table, left.get(index), right.get(index), names, inferred); index += 1;
    }
}

pub struct GenericInference {
    pub let arena: AstArena;
    pub let type_table: TypeTable;
    pub let symbol_table: SymbolTable;
    pub let type_resolver: TypeResolver;
    pub let expr_types: Dict<i32, TypeId>;
    var infer_expression: ((NodeId, TypeId?) -> TypeId)?;
    let error_reporter: ((TypeErrorKind, String) -> Void)?;
    let members: MemberResolver;
    pub def set_infer_expression(callback: ((NodeId, TypeId?) -> TypeId)?) -> Void { self.infer_expression = callback; }
    pub static def new(arena: AstArena, types: TypeTable, symbols: SymbolTable, resolver: TypeResolver,
                       expr_types: Dict<i32, TypeId>, infer_expression: ((NodeId, TypeId?) -> TypeId)? = nil,
                       error_reporter: ((TypeErrorKind, String) -> Void)? = nil) -> GenericInference {
        GenericInference { arena, type_table: types, symbol_table: symbols, type_resolver: resolver,
            expr_types, infer_expression, error_reporter, members: MemberResolver.new(arena, types, symbols) }
    }
    pub def make_generic_param_type_args(params: Vec<NodeId>) -> Vec<TypeId> {
        let args = Vec<TypeId>.new();
        for id in params {
            if let node = self.arena.get(id) {
                switch node.form {
                    case .generic_param(let data):
                        let bounds = Vec<TypeId>.new();
                        if let declared = data.bounds {
                            for bound in declared { let type = self.type_resolver.resolve(bound); if !self.type_table.is_error(type) { bounds.push(type); } }
                        }
                        args.push(self.type_table.make_type_variable(data.name, bounds));
                    default: {}
                }
            }
        }
        args
    }
    pub def infer_type_node_generics(node: NodeId?, concrete: TypeId, names: Dict<String, Bool>, inferred: Dict<String, TypeId>) -> Void {
        guard let id = node else { return; }
        let mapping = Dict<String, TypeId>.with_capacity(16, 1);
        for entry in inferred.entries() { mapping[entry.key] = entry.value; }
        for entry in names.entries() { mapping[entry.key] = self.type_table.make_type_variable(entry.key); }
        let pattern = self.type_resolver.resolve(id, mapping);
        infer_resolved_type_arguments(self.type_table, pattern, concrete, names, inferred);
    }
    pub def substitute_type(type: TypeId, mapping: Dict<String, TypeId>) -> TypeId {
        self.members.substitute_member_type(type, mapping)
    }
    pub def get_function_type(symbol: Symbol) -> TypeId {
        guard let id = symbol.decl_node else { return self.type_table.error_type; }
        guard let node = self.arena.get(id) else { return self.type_table.error_type; }
        switch node.form {
            case .func_decl(let data): return self.function_type(data.params, data.return_type, data.is_async);
            case .extern_func_decl(let data): return self.function_type(data.params, data.return_type, data.is_async);
            default: {}
        }
        self.type_table.error_type
    }
    def function_type(params: Vec<NodeId>, ret: NodeId?, async: Bool) -> TypeId {
        let types = Vec<TypeId>.new();
        for param in params { types.push(self.type_resolver.resolve(self.param_annotation(param))); }
        var result = self.type_table.void_type;
        if let annotation = ret { result = self.type_resolver.resolve(annotation); }
        self.type_table.make_function(types, result, async)
    }
    def param_annotation(id: NodeId) -> NodeId? {
        if let node = self.arena.get(id) { switch node.form { case .param(let data): return data.type_annotation; default: {} } }
        nil
    }
    def infer(id: NodeId, context: TypeId?) -> TypeId {
        if let callback = self.infer_expression { return callback(id, context); }
        self.expr_types[id.id] ?? self.type_table.error_type
    }
    def find_method_owner(method: NodeId) -> NodeId? {
        for entry in self.symbol_table.symbols.entries() {
            if let id = entry.value.decl_node {
                if let node = self.arena.get(id) {
                    var members: Vec<NodeId>? = nil;
                    switch node.form {
                        case .struct_decl(let data): members = data.members;
                        case .enum_decl(let data): members = data.members;
                        case .extension_decl(let data): members = data.members;
                        default: {}
                    }
                    if let children = members { for child in children { if child == method { return id; } } }
                }
            }
        }
        nil
    }
    pub def infer_generic_call_args(callee: SymbolId, call_id: NodeId, expected: TypeId? = nil) -> Dict<String, TypeId> {
        let inferred = Dict<String, TypeId>.with_capacity(16, 1);
        guard let symbol = self.symbol_table.get_symbol(callee) else { return inferred; }
        guard let decl_id = symbol.decl_node else { return inferred; }
        guard let decl_node = self.arena.get(decl_id) else { return inferred; }
        guard let decl = generic_function_form(decl_node) else { return inferred; }
        guard let call_node = self.arena.get(call_id) else { return inferred; }
        guard let call = generic_call_form(call_node) else { return inferred; }
        var receiver: NodeId? = nil;
        if let callee_id = call.callee {
            if let node = self.arena.get(callee_id) { switch node.form { case .member_access(let data): receiver = data.object; default: {} } }
        }
        if decl.generic_params.len() == 0 { if let object = receiver {} else { return inferred; } }
        let names = Dict<String, Bool>.with_capacity(16, 1);
        for id in decl.generic_params {
            if let node = self.arena.get(id) { switch node.form { case .generic_param(let data): names[data.name] = true; default: {} } }
        }
        var nominal_owner = false;
        if let object = receiver {
            if let owner_id = self.find_method_owner(decl_id) {
                if let owner = self.arena.get(owner_id) {
                    let params = Vec<NodeId>.new();
                    switch owner.form {
                        case .struct_decl(let data): for id in data.generic_params { params.push(id); } nominal_owner = true;
                        case .enum_decl(let data): for id in data.generic_params { params.push(id); } nominal_owner = true;
                        case .extension_decl(let data): for id in data.generic_params { params.push(id); }
                        default: {}
                    }
                    if let type = self.expr_types[object.id] {
                        if let info = self.type_table.get_type(type) {
                            var args = FrozenVec<TypeId>.empty();
                            switch info.data { case .struct_type(let data): args = data.type_args; case .enum_type(let data): args = data.type_args; default: {} }
                            var index = 0;
                            while index < params.len() && index < args.len() {
                                if let param = self.arena.get(params[index]) {
                                    switch param.form { case .generic_param(let data): inferred[data.name] = args.get(index); default: {} }
                                }
                                index += 1;
                            }
                        }
                    }
                }
            }
        }
        if let type = expected { self.infer_type_node_generics(decl.return_type, type, names, inferred); }
        // A callback can precede the collection argument that determines its
        // parameter type; infer ordinary arguments before lambdas.
        for lambda_pass in 0..<2 {
            for index in 0..<call.arguments.len() {
                if index >= decl.params.len() { continue; }
                guard let argument = self.arena.get(call.arguments[index]) else { continue; }
                guard let arg = generic_argument_form(argument) else { continue; }
                guard let value = arg.value else { continue; }
                guard let value_node = self.arena.get(value) else { continue; }
                var lambda = false;
                switch value_node.form {
                    case .lambda: lambda = true;
                    // Empty literals carry no type information; they are checked against the
                    // inferred parameter type afterwards.
                    case .array_literal(let literal): if literal.elements.len() == 0 { continue; }
                    case .dict_literal(let literal): if literal.entries.len() == 0 { continue; }
                    default: {}
                }
                if lambda != (lambda_pass == 1) { continue; }
                let annotation = self.param_annotation(decl.params[index]);
                var actual = self.type_table.error_type;
                if lambda { actual = self.infer(value, self.type_resolver.resolve(annotation, inferred)); }
                else {
                    if let cached = self.expr_types[value.id] { actual = cached; }
                    else { actual = self.infer(value, nil); }
                }
                self.infer_type_node_generics(annotation, actual, names, inferred);
            }
        }
        if nominal_owner {
            let filtered = Dict<String, TypeId>.with_capacity(16, 1);
            for entry in inferred.entries() { if names.contains(entry.key) { filtered[entry.key] = entry.value; } }
            return filtered;
        }
        inferred
    }
    // A type parameter argument satisfies a protocol through its own bounds: the same protocol,
    // or one whose (inherited, flattened) requirements include all of the protocol's.
    pub def bound_satisfies(concrete: TypeId, protocol: TypeId) -> Bool {
        guard let info = self.type_table.get_type(concrete) else { return false; }
        var bounds = FrozenVec<TypeId>.empty(); switch info.data { case .type_variable(let data): bounds = data.bounds; default: return false; }
        guard let wanted = self.protocol_data(protocol) else { return false; }
        for bound in bounds {
            if bound == protocol { return true; }
            if let have = self.protocol_data(bound) {
                var covered = true;
                for req in wanted.func_requirements { var found = false; for other in have.func_requirements { if other.name.equals(req.name) { found = true; } } if !found { covered = false; } }
                for req in wanted.prop_requirements { var found = false; for other in have.prop_requirements { if other.name.equals(req.name) { found = true; } } if !found { covered = false; } }
                if covered { return true; }
            }
        }
        false
    }
    def protocol_data(type: TypeId) -> ProtocolTypeData? {
        if let info = self.type_table.get_type(type) { switch info.data { case .protocol(let data): return data; default: {} } }
        nil
    }
    // `checker` must be the checker that has seen extension conformances.
    pub def check_generic_constraints(inferred: Dict<String, TypeId>, params: Vec<NodeId>, checker: ConformanceChecker) -> Void {
        for id in params {
            guard let node = self.arena.get(id) else { continue; }
            switch node.form {
                case .generic_param(let param):
                    guard let concrete = inferred[param.name] else { continue; }
                    if let bounds = param.bounds {
                        for bound in bounds {
                            let protocol = self.type_resolver.resolve(bound);
                            if self.type_table.is_error(protocol) || !self.type_table.is_protocol(protocol) { continue; }
                            if !self.bound_satisfies(concrete, protocol) && !checker.check_conformance(concrete, protocol).conforms {
                                var name = "";
                                if let annotation = self.arena.get(bound) { switch annotation.form { case .named_type(let data): name = data.name; default: {} } }
                                if let report = self.error_reporter {
                                    report(TypeErrorKind.type_mismatch(), f"Type '{self.type_table.format_type(concrete)}' does not conform to protocol '{self.type_table.format_type(protocol)}' (required by '{param.name}: {name}')");
                                }
                            }
                        }
                    }
                default: {}
            }
        }
    }
}
def generic_function_form(node: AstNode) -> FuncDeclAst? { switch node.form { case .func_decl(let data): data; default: nil; } }
def generic_call_form(node: AstNode) -> CallAst? { switch node.form { case .call(let data): data; default: nil; } }
def generic_argument_form(node: AstNode) -> ArgumentAst? { switch node.form { case .argument(let data): data; default: nil; } }
