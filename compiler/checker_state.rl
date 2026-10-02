// Shared bidirectional checking state. Components call through scoped callbacks
// rather than importing each other; TypeChecker binds and clears them per run.
pub import "generic_inference.rl"
pub import "member_resolver.rl"
pub import "layout.rl"
pub import "exhaustiveness.rl"
pub import "operators.rl"
import std.collections

pub struct CheckerState {
    pub let arena: AstArena;
    pub let resolution: ResolutionResult;
    pub let symbol_table: SymbolTable;
    pub let node_symbols: Dict<i32, SymbolId>;
    pub let type_table: TypeTable;
    pub let type_resolver: TypeResolver;
    pub let member_resolver: MemberResolver;
    pub let conformance_checker: ConformanceChecker;
    pub let generic_inference: GenericInference;
    pub let layout: LayoutService;
    pub let result: TypeCheckResult;
    pub let type_env: Dict<i32, TypeId>;
    // Synthetic ASTs hold checker annotations without mutating the
    // source schema. HIR can consume these rewrites using stable NodeIds.
    pub let lowered_expressions: Dict<i32, NodeId>;
    pub var current_function_return: TypeId?;
    pub var current_self_type: TypeId?;
    pub var expected_type: TypeId?;
    pub var in_async_function: Bool;
    pub var in_unsafe: Bool;
    // `where C.Item == T` constraints of the function being checked, keyed by projection name.
    pub var projection_equalities: Dict<String, TypeId>;
    let computing_constants: Dict<i32, Bool>;
    // Generic parameters declared by the function and type being checked. Unlike inference
    // variables they are fixed: a T value is only a T (or an `any P` for a bound P).
    pub var rigid_generics: Dict<String, Bool>;
    // Function types of closures the checker synthesizes, used as their parameter context.
    pub let synthetic_lambda_types: Dict<i32, TypeId>;
    pub var infer_callback: ((NodeId) -> TypeId)?;
    pub var statement_callback: ((NodeId) -> Void)?;
    // The innermost located node and file being checked, for errors reported without a node.
    pub var current_node: NodeId?;
    pub var current_file: String?;
    pub static def new(arena: AstArena, resolution: ResolutionResult) -> CheckerState {
        let types = TypeTable.new(); types.attach_symbol_table(resolution.symbol_table);
        let result = TypeCheckResult.new(types);
        let errors = result.errors;
        let resolver = TypeResolver.new(arena, types, resolution.symbol_table,
            resolution.node_symbols, resolution.imported_symbols,
            (kind: String, message: String, id: NodeId?) -> {
                var error_kind = TypeErrorKind.not_a_type();
                if kind.equals("GENERIC_ARG_COUNT") { error_kind = TypeErrorKind.generic_arg_count(); }
                var span: Span? = nil; var file: String? = nil;
                if let ref = id { if let node = arena.get(ref) { span = node.span; } file = arena.source_module(ref); }
                errors.push(TypeError { kind: error_kind, message, span, file });
            });
        let state = CheckerState { arena, resolution, symbol_table: resolution.symbol_table, node_symbols: resolution.node_symbols,
            type_table: types, type_resolver: resolver,
            member_resolver: MemberResolver.new(arena, types, resolution.symbol_table),
            conformance_checker: ConformanceChecker.new(arena, types, resolution.symbol_table),
            generic_inference: GenericInference.new(arena, types, resolution.symbol_table, resolver, result.expr_types),
            layout: LayoutService.new(arena, types, resolution.symbol_table, resolver), result,
            type_env: Dict<i32, TypeId>.with_capacity(16, 0), lowered_expressions: result.lowered_expressions,
            current_function_return: nil, current_self_type: nil, expected_type: nil,
            in_async_function: false, in_unsafe: false, projection_equalities: Dict<String, TypeId>.with_capacity(4, 1), computing_constants: Dict<i32, Bool>.with_capacity(4, 0), rigid_generics: Dict<String, Bool>.with_capacity(4, 1), synthetic_lambda_types: Dict<i32, TypeId>.with_capacity(4, 0), infer_callback: nil, statement_callback: nil, current_node: nil, current_file: nil };
        // Inference errors are located at the expression being checked.
        state.generic_inference.error_reporter = (kind: TypeErrorKind, message: String) -> { state.error(kind, message); };
        state
    }
    pub def error(kind: TypeErrorKind, message: String, id: NodeId? = nil) -> Void {
        // An operand whose type is already an error was reported where it arose.
        if message.contains("<error>") && (self.result.errors.len() > 0 || self.resolution.errors.len() > 0) { return; }
        var located = self.current_node;
        if let ref = id { if let node = self.arena.get(ref) { if let span = node.span { located = ref; } } }
        var span: Span? = nil;
        var file = self.current_file;
        if let ref = located {
            if let node = self.arena.get(ref) { span = node.span; }
            if let module = self.arena.source_module(ref) { file = module; }
        }
        self.result.errors.push(TypeError { kind, message, span, file });
    }
    // Makes `id` the location of errors reported without a node when it has a
    // source span; returns the previous location for restoring.
    pub def locate(id: NodeId) -> NodeId? {
        let previous = self.current_node;
        if let node = self.arena.get(id) { if let span = node.span { self.current_node = id; } }
        previous
    }
    pub def builtin(name: String) -> TypeId { self.type_table.get_builtin(name) ?? self.type_table.error_type }
    pub def resolve_type(id: NodeId?) -> TypeId { self.with_equalities(self.type_resolver.resolve(id)) }
    pub def constant_decl(sid: SymbolId) -> ConstantDeclAst? {
        if let symbol = self.symbol_table.get_symbol(sid) { if let decl = symbol.decl_node { if let node = self.arena.get(decl) { switch node.form { case .constant_decl(let data): return data; default: {} } } } }
        nil
    }
    // Type of a module-level constant, checked on first use (also across modules).
    pub def constant_type(sid: SymbolId, data: ConstantDeclAst) -> TypeId {
        if let known = self.type_env[sid.id] { return known; }
        if self.computing_constants.contains(sid.id) {
            self.error(TypeErrorKind.invalid_operation(), f"Constant '{data.name}' depends on itself", data.value);
            self.type_env[sid.id] = self.type_table.error_type; return self.type_table.error_type;
        }
        self.computing_constants[sid.id] = true;
        defer { self.computing_constants.remove(sid.id); }
        let old_return = self.current_function_return; let old_equalities = self.projection_equalities;
        self.current_function_return = nil; self.projection_equalities = Dict<String, TypeId>.with_capacity(4, 1);
        defer { self.current_function_return = old_return; self.projection_equalities = old_equalities; }
        var expected: TypeId? = nil; if let annotation = data.type_annotation { expected = self.resolve_type(annotation); }
        let actual = self.infer_with_expected(data.value, expected);
        var type = actual;
        if let declared = expected { self.check_assignable(actual, declared, f"constant '{data.name}'", data.value); type = declared; }
        if !self.type_table.is_error(type) {
            if !self.is_constant_expression(data.value) {
                self.error(TypeErrorKind.invalid_operation(), f"The value of constant '{data.name}' must be a constant expression (literals, operators, casts and other constants)", data.value);
            } else if !self.is_constant_type(type) {
                self.error(TypeErrorKind.type_mismatch(), f"Constant '{data.name}' has type {self.type_table.format_type(type)}; constants must be numbers, Bool, String or optionals of them", data.value);
            }
        }
        self.type_env[sid.id] = type; type
    }
    // Constants are inlined at each use, so their values must not depend on evaluation or identity.
    def is_constant_expression(id: NodeId?) -> Bool {
        guard let ref = id else { return false; }
        guard let node = self.arena.get(ref) else { return false; }
        switch node.form {
            case .literal: return true;
            case .unary_op(let data): return !self.result.operator_targets.contains(ref.id) && self.is_constant_expression(data.operand);
            case .binary_op(let data):
                // Only String's + is an overloaded operator on constant types.
                if self.result.operator_targets.contains(ref.id) { if let left = data.left { if let type = self.result.expr_types[left.id] { if !self.type_table.is_string(type) { return false; } } } }
                return self.is_constant_expression(data.left) && self.is_constant_expression(data.right);
            case .ternary_op(let data): return self.is_constant_expression(data.condition) && self.is_constant_expression(data.then_expr) && self.is_constant_expression(data.else_expr);
            case .cast(let data): return self.is_constant_expression(data.expr);
            case .identifier: if let sid = self.node_symbols[ref.id] { if let constant = self.constant_decl(sid) { return true; } } return false;
            default: return false;
        }
    }
    def is_constant_type(type: TypeId) -> Bool {
        let inner = self.type_table.get_optional_inner(type) ?? type;
        if self.type_table.is_string(inner) { return true; }
        if let info = self.type_table.get_type(inner) { switch info.data { case .primitive(let primitive): switch primitive { case .void_type | .raw_ptr: return false; default: return true; } default: {} } }
        false
    }
    pub def with_equalities(type: TypeId) -> TypeId {
        if self.projection_equalities.len() == 0 { return type; }
        self.generic_inference.substitute_type(type, self.projection_equalities)
    }
    // Equality constraints such as `where C.Item == i32`, as (projection, required type) pairs.
    pub def equality_constraints(constraints: Vec<NodeId>) -> Vec<(TypeId, TypeId)> {
        let pairs = Vec<(TypeId, TypeId)>.new();
        for id in constraints { if let node = self.arena.get(id) { switch node.form { case .constraint(let data): if data.kind.equals("equals") {
            if let subject = data.subject { switch subject { case .type_ref(let ref): pairs.push((self.type_resolver.resolve(ref), self.type_resolver.resolve(data.equal_type))); default: {} } }
        } default: {} } } }
        pairs
    }
    pub def infer_expr(id: NodeId?) -> TypeId {
        if let ref = id { if let callback = self.infer_callback {
            let previous = self.locate(ref);
            defer { self.current_node = previous; }
            return callback(ref);
        } }
        self.type_table.error_type
    }
    pub def infer_with_expected(id: NodeId?, expected: TypeId?) -> TypeId {
        let previous = self.expected_type; self.expected_type = expected;
        defer { self.expected_type = previous; }
        self.infer_expr(id)
    }
    pub def check_stmt(id: NodeId?) -> Void {
        if let ref = id { if let callback = self.statement_callback {
            let previous = self.locate(ref);
            defer { self.current_node = previous; }
            callback(ref);
        } }
    }
    pub def check_block(id: NodeId?) -> Void {
        guard let ref = id else { return; }
        guard let node = self.arena.get(ref) else { return; }
        switch node.form {
            case .block(let data):
                let previous = self.in_unsafe;
                if data.is_unsafe { self.in_unsafe = true; }
                defer { self.in_unsafe = previous; }
                for stmt in data.statements { self.check_stmt(stmt); }
            default: {}
        }
    }
    pub def require_unsafe(operation: String, id: NodeId? = nil) -> Void {
        if !self.in_unsafe { self.error(TypeErrorKind.invalid_operation(), operation + " is unsafe and must be used inside an unsafe block", id); }
    }
    pub def is_raw_ptr(type: TypeId) -> Bool { type == self.builtin("RawPtr") }
    pub def check_boolean(type: TypeId, context: String) -> Void {
        if !self.type_table.is_bool(type) && !self.type_table.is_error(type) {
            self.error(TypeErrorKind.type_mismatch(), f"Expected Bool for {context}, got {self.type_table.format_type(type)}");
        }
    }
    pub def param(id: NodeId) -> ParamAst? {
        if let node = self.arena.get(id) { switch node.form { case .param(let data): return data; default: {} } }
        nil
    }
    pub def function(id: NodeId?) -> FuncDeclAst? {
        if let ref = id { if let node = self.arena.get(ref) { switch node.form { case .func_decl(let data): return data; default: {} } } }
        nil
    }
    pub def generic_name(id: NodeId) -> String {
        if let node = self.arena.get(id) { switch node.form { case .generic_param(let data): return data.name; default: {} } }
        ""
    }
    pub def generic_names(params: Vec<NodeId>) -> Dict<String, Bool> {
        let names = Dict<String, Bool>.with_capacity(16, 1);
        for id in params { names[self.generic_name(id)] = true; }
        names
    }
    pub def record_call(id: NodeId, kind: CalleeKind, symbol: SymbolId? = nil, name: String? = nil) -> Void {
        self.result.call_targets[id.id] = CalleeId { kind, symbol_id: symbol, case_name: name };
    }
    pub def enum_decl(type: TypeId) -> EnumDeclAst? {
        if let info = self.type_table.get_type(type) {
            switch info.data {
                case .enum_type(let data):
                    if let symbol = self.symbol_table.get_symbol(data.symbol_id) {
                        if let id = symbol.decl_node { if let node = self.arena.get(id) { switch node.form { case .enum_decl(let decl): return decl; default: {} } } }
                    }
                default: {}
            }
        }
        nil
    }
    pub def lookup_enum_case(type: TypeId, name: String) -> EnumCaseDefAst? {
        if let decl = self.enum_decl(type) {
            for member in decl.members {
                if let node = self.arena.get(member) {
                    switch node.form {
                        case .enum_case_decl(let group):
                            for case_id in group.cases { if let case_node = self.arena.get(case_id) { switch case_node.form { case .enum_case_def(let data): if data.name.equals(name) { return data; } default: {} } } }
                        default: {}
                    }
                }
            }
        }
        nil
    }
    pub def enum_case_type(symbol: Symbol) -> TypeId {
        for entry in self.symbol_table.symbols.entries() {
            switch entry.value.kind { case .enum_type: {} default: continue; }
            let type = self.type_table.make_enum(entry.value.id);
            if let data = self.lookup_enum_case(type, symbol.name) { return type; }
        }
        self.type_table.error_type
    }
    pub def bind_pattern(id: NodeId?, type: TypeId) -> Void {
        guard let ref = id else { return; }
        guard let node = self.arena.get(ref) else { return; }
        switch node.form {
            case .identifier_pattern:
                if let symbol = self.node_symbols[ref.id] { self.type_env[symbol.id] = type; }
            case .tuple_pattern(let data):
                var fields = FrozenVec<TupleField>.empty();
                var tuple = false;
                if let info = self.type_table.get_type(type) {
                    switch info.data {
                        case .struct_type(let value): if let symbol = value.symbol_id {} else { tuple = true; fields = value.anon_fields ?? FrozenVec<TupleField>.empty(); }
                        default: {}
                    }
                }
                if tuple {
                    if data.elements.len() != fields.len() { self.error(TypeErrorKind.type_mismatch(), f"tuple pattern has {data.elements.len()} elements but value has {fields.len()}", ref); }
                } else if !self.type_table.is_error(type) { self.error(TypeErrorKind.type_mismatch(), "tuple pattern requires a tuple value", ref); }
                for index in 0..<data.elements.len() {
                    let pair = data.elements[index];
                    var bound = self.type_table.error_type;
                    if index < fields.len() {
                        let field = fields.get(index); bound = field.type_id;
                        if let label = pair.0 { if !label.equals(field.name) { self.error(TypeErrorKind.type_mismatch(), f"tuple pattern label '{label}' does not match '{field.name}'", ref); } }
                    }
                    self.bind_pattern(pair.1, bound);
                }
            case .enum_case_pattern(let data):
                if let decl = self.enum_decl(type) {
                    let subst = Dict<String, TypeId>.with_capacity(16, 1);
                    if let info = self.type_table.get_type(type) {
                        switch info.data { case .enum_type(let value): if value.type_args.len() == decl.generic_params.len() { for index in 0..<decl.generic_params.len() { subst[self.generic_name(decl.generic_params[index])] = value.type_args.get(index); } } default: {} }
                    }
                    if let member = self.lookup_enum_case(type, data.case_name) {
                        for index in 0..<data.payload.len() { if index < member.payload.len() { self.bind_pattern(data.payload[index], self.generic_inference.substitute_type(self.resolve_type(member.payload[index].1), subst)); } }
                    }
                } else if data.case_name.equals("Some") {
                    if let inner = self.type_table.get_optional_inner(type) { for pattern in data.payload { self.bind_pattern(pattern, inner); } }
                }
            case .typed_pattern(let data):
                var bound = type;
                if let annotation = data.type_annotation { bound = self.resolve_type(annotation); }
                self.bind_pattern(data.pattern, bound);
            case .or_pattern(let data): for pattern in data.patterns { self.bind_pattern(pattern, type); }
            default: {}
        }
    }
    pub def common_numeric_type(left: TypeId, right: TypeId) -> TypeId {
        let table = self.type_table;
        if table.is_float(left) || table.is_float(right) {
            let f64 = self.builtin("f64"); if left == f64 || right == f64 { return f64; }
            if table.is_float(left) { return left; } return right;
        }
        if !table.is_integer(left) || !table.is_integer(right) { return left; }
        let a = integer_width(table, left); let b = integer_width(table, right);
        let sa = table.is_signed_integer(left); let sb = table.is_signed_integer(right);
        if sa == sb { if a >= b { return left; } return right; }
        if sa && a > b { return left; } if sb && b > a { return right; }
        self.builtin("i64")
    }
    pub def try_operator_overload(id: NodeId?, left: TypeId, op: String, right: TypeId) -> TypeId? {
        let name = to_method_name(op);
        if name.is_empty() { return nil; }
        if let method = self.member_resolver.get_method(left, name) {
            if let info = self.type_table.get_type(method.signature) {
                switch info.data {
                    case .function(let data):
                        if data.params.len() > 0 && self.types_equal(right, data.params.get(0)) {
                            if let ref = id { self.result.operator_targets[ref.id] = CalleeId { kind: CalleeKind.method(), symbol_id: method.symbol_id, case_name: nil }; }
                            return data.return_type;
                        }
                    default: {}
                }
            }
        }
        nil
    }
    // `indices` must match the leading parameters of a __get__/__set__ method; `extra` counts trailing value parameters.
    pub def check_subscript_indices(func: FunctionTypeData, indices: Vec<NodeId>, extra: i32, method: String, id: NodeId) -> Void {
        let expected = func.params.len() - extra;
        if expected != indices.len() { self.error(TypeErrorKind.wrong_arg_count(), f"{method} takes {expected} index value(s), got {indices.len()}", id); return; }
        for index in 0..<indices.len() { if let actual = self.result.expr_types[indices[index].id] {
            self.check_assignable(actual, func.params.get(index), f"subscript index {index + 1}", indices[index]);
        } }
    }
    pub def try_unary_overload(id: NodeId, operand: TypeId, op: String) -> TypeId? {
        let name = to_unary_method_name(op);
        if name.is_empty() { return nil; }
        guard let method = self.member_resolver.get_method(operand, name) else { return nil; }
        guard let data = self.type_table.get_function_data(method.signature) else { return nil; }
        if data.params.len() != 0 { return nil; }
        self.result.operator_targets[id.id] = CalleeId { kind: CalleeKind.method(), symbol_id: method.symbol_id, case_name: nil };
        data.return_type
    }
    pub def binary_types(left: TypeId, op: String, right: TypeId, emit_error: Bool = true) -> TypeId {
        let table = self.type_table;
        if is_arithmetic_op(op) {
            if table.is_numeric(left) && table.is_numeric(right) { return self.common_numeric_type(left, right); }
            if emit_error { self.error(TypeErrorKind.invalid_operation(), f"Cannot apply '{op}' to {table.format_type(left)} and {table.format_type(right)}"); }
        } else if is_order_comparison_op(op) || is_equality_op(op) {
            if is_equality_op(op) {
                if table.is_error(left) || table.is_error(right) { return self.builtin("Bool"); }
                if let a = table.get_type(left) { if let b = table.get_type(right) {
                    switch a.data { case .primitive: switch b.data { case .primitive: if left == right { return self.builtin("Bool"); } default: {} } default: {} }
                } }
            }
            if table.is_numeric(left) && table.is_numeric(right) { return self.builtin("Bool"); }
            if emit_error {
                if right == table.nil_type { self.error(TypeErrorKind.invalid_operation(), f"Cannot compare {table.format_type(left)} with nil: {table.format_type(left)} is not optional"); }
                else if left == table.nil_type { self.error(TypeErrorKind.invalid_operation(), f"Cannot compare nil with {table.format_type(right)}: {table.format_type(right)} is not optional"); }
                else { self.error(TypeErrorKind.invalid_operation(), f"Cannot compare {table.format_type(left)} and {table.format_type(right)}"); }
            }
        } else if is_logical_op(op) {
            self.check_boolean(left, "left operand"); self.check_boolean(right, "right operand"); return self.builtin("Bool");
        } else if is_nil_coalescing_op(op) { return table.get_optional_inner(left) ?? left; }
        else if is_bitwise_op(op) {
            if table.is_integer(left) && table.is_integer(right) { return left; }
            if emit_error { self.error(TypeErrorKind.invalid_operation(), "Bitwise operation requires integer operands"); }
        }
        table.error_type
    }
    pub def types_equal(left: TypeId, right: TypeId) -> Bool { self.type_table.types_equal(left, right) }
    pub def is_rigid(type: TypeId) -> Bool {
        guard let info = self.type_table.get_type(type) else { return false; }
        switch info.data { case .type_variable(let variable): return variable.name.find(".") >= 0 || self.rigid_generics.contains(variable.name); default: {} }
        false
    }
    pub def check_assignable(source: TypeId, target: TypeId, context: String, id: NodeId? = nil) -> Void {
        let table = self.type_table;
        if table.is_error(source) || table.is_error(target) || self.types_equal(source, target) { return; }
        // Inference variables are resolved later; declared generic parameters and projections
        // such as C.Item only match themselves.
        if !self.is_rigid(target) { if let info = table.get_type(target) { switch info.data { case .type_variable: return; default: {} } } }
        // A value may be wrapped by every optional layer of the target, e.g. i32 into (i32?)?.
        var layer = target; var wrapping = true;
        while wrapping {
            if let inner = table.get_optional_inner(layer) {
                if self.types_equal(source, inner) || table.can_widen_int(source, inner) { return; }
                layer = inner;
            } else { wrapping = false; }
        }
        if let info = table.get_type(target) {
            switch info.data {
                case .existential(let data):
                    if self.generic_inference.bound_satisfies(source, data.protocol_id) { return; }
                    let result = self.conformance_checker.check_conformance(source, data.protocol_id);
                    if result.conforms { return; }
                    var details = "";
                    if result.missing_requirements.len() > 0 { details = "; missing requirements: " + join_strings(result.missing_requirements, ", "); }
                    else if result.errors.len() > 0 { details = "; " + result.errors[0]; }
                    self.error(TypeErrorKind.type_mismatch(), f"Type {table.format_type(source)} does not conform to {table.format_type(data.protocol_id)}{details} in {context}", id); return;
                default: {}
            }
        }
        if source == table.nil_type {
            if let inner = table.get_optional_inner(target) { return; }
            if self.is_raw_ptr(target) { return; }
            self.error(TypeErrorKind.type_mismatch(), f"Cannot assign nil to non-optional type {table.format_type(target)} in {context}", id); return;
        }
        if !self.is_rigid(source) { if let info = table.get_type(source) { switch info.data { case .type_variable: return; default: {} } } }
        if table.is_never(source) || table.can_widen_int(source, target) { return; }
        self.error(TypeErrorKind.type_mismatch(), f"Cannot assign {table.format_type(source)} to {table.format_type(target)} in {context}", id);
    }
    pub def iterable_element(type: TypeId) -> TypeId {
        var indexable = false;
        if let info = self.type_table.get_type(type) { switch info.data { case .struct_type: indexable = true; default: {} } }
        if indexable { if let len = self.member_resolver.get_method(type, "len") {
            if let get = self.member_resolver.get_method(type, "get") {
                if let ld = self.type_table.get_function_data(len.signature) {
                    if ld.params.len() == 0 && ld.return_type == self.builtin("i32") {
                        if let gd = self.type_table.get_function_data(get.signature) { if gd.params.len() >= 1 { return gd.return_type; } }
                    }
                }
            }
        } }
        if let protocol = self.symbol_table.get_builtin("Iterable") {
            let p = self.type_table.get_protocol_type(protocol);
            if self.conformance_checker.check_conformance(type, p).conforms {
                if let iterator = self.member_resolver.get_method(type, "__iter__") {
                    if let signature = self.type_table.get_function_data(iterator.signature) {
                        if let next = self.member_resolver.get_method(signature.return_type, "__next__") {
                            if let data = self.type_table.get_function_data(next.signature) { return self.type_table.get_optional_inner(data.return_type) ?? self.type_table.error_type; }
                        }
                    }
                }
            }
        }
        self.type_table.error_type
    }
    pub def block_statements(id: NodeId?) -> Vec<NodeId> {
        if let ref = id { if let node = self.arena.get(ref) { switch node.form { case .block(let data): return data.statements; default: {} } } }
        Vec<NodeId>.new()
    }
    pub def definitely_returns(stmts: Vec<NodeId>) -> Bool {
        for id in stmts { if self.statement_returns(id) { return true; } }
        false
    }
    pub def statement_returns(id: NodeId?) -> Bool {
        guard let ref = id else { return false; }
        guard let node = self.arena.get(ref) else { return false; }
        switch node.form {
            case .return_stmt: return true;
            case .block(let data): return self.definitely_returns(data.statements);
            case .if_stmt(let data): return self.definitely_returns(self.block_statements(data.then_block)) && self.statement_returns(data.else_block);
            case .switch_stmt(let data):
                if data.cases.len() == 0 { return false; }
                for id in data.cases { if let branch = self.arena.get(id) { switch branch.form { case .switch_case(let data): if !self.definitely_returns(data.body) { return false; } default: return false; } } }
                return true;
            default: {}
        }
        false
    }
    pub def block_diverges(id: NodeId?) -> Bool {
        let stmts = self.block_statements(id);
        if stmts.len() == 0 { return false; }
        self.statement_diverges(stmts[stmts.len() - 1])
    }
    pub def statement_diverges(id: NodeId?) -> Bool {
        guard let ref = id else { return false; }
        guard let node = self.arena.get(ref) else { return false; }
        switch node.form {
            case .return_stmt, .break_stmt, .continue_stmt: return true;
            case .block: return self.block_diverges(ref);
            case .if_stmt(let data): return self.block_diverges(data.then_block) && self.statement_diverges(data.else_block);
            case .switch_stmt(let data):
                if data.cases.len() == 0 { return false; }
                var default_case = false;
                for id in data.cases {
                    guard let branch = self.arena.get(id) else { return false; }
                    switch branch.form {
                        case .switch_case(let data): if data.is_default { default_case = true; } if data.body.len() == 0 || !self.statement_diverges(data.body[data.body.len() - 1]) { return false; }
                        default: return false;
                    }
                }
                return default_case;
            default: {}
        }
        false
    }
}
pub def integer_width(table: TypeTable, type: TypeId) -> i32 {
    if let info = table.get_type(type) { switch info.data { case .primitive(let p): return p.integer_width(); default: {} } }
    0
}
