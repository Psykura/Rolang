// Bidirectional expression checking. Semantic annotations live in NodeId tables.
pub import "checker_state.rl"
import std.collections
pub struct ExprChecker {
    pub let state: CheckerState;
    var spawn_call: NodeId?;
    var callee: NodeId?;
    pub static def new(state: CheckerState) -> ExprChecker { ExprChecker { state, spawn_call: nil, callee: nil } }
    pub def infer_expr(id: NodeId) -> TypeId {
        guard let node = self.state.arena.get(id) else { return self.state.type_table.error_type; }
        var type = self.infer(id, node.form);
        switch node.form {
            case .call(let data): if data.is_interpolation && !self.state.type_table.is_error(type) {
                if let symbol = self.state.symbol_table.get_type_symbol("String") {
                    if !self.state.types_equal(type, self.state.type_table.make_struct(symbol)) { self.state.error(TypeErrorKind.type_mismatch(), "Interpolation requires to_string() to return String"); type = self.state.type_table.error_type; }
                }
            }
            default: {}
        }
        self.state.result.expr_types[id.id] = type;
        type
    }
    def infer(id: NodeId, form: NodeForm) -> TypeId {
        switch form {
            case .literal(let data): return self.literal(id, data);
            case .identifier: return self.identifier(id);
            case .type_reference(let data): return self.state.resolve_type(data.type_name);
            case .binary_op(let data): return self.binary(id, data);
            case .unary_op(let data): return self.unary(id, data);
            case .ternary_op(let data): return self.ternary(data);
            case .call(let data): return self.call(id, data);
            case .member_access(let data): return self.member(id, data);
            case .subscript(let data): return self.subscript_expr(id, data);
            case .tuple_expr(let data):
                // A contextual tuple type supplies element types, e.g. nil for an optional element.
                var expected_fields: FrozenVec<TupleField>? = nil;
                if let expected = self.state.expected_type { if let info = self.state.type_table.get_type(self.state.type_table.get_optional_inner(expected) ?? expected) { switch info.data {
                    case .struct_type(let value): if let symbol = value.symbol_id {} else { if let anon = value.anon_fields { if anon.len() == data.elements.len() { expected_fields = anon; } } }
                    default: {}
                } } }
                let fields = Vec<(String?, TypeId)>.new();
                for index in 0..<data.elements.len() { let pair = data.elements[index];
                    if let context = expected_fields { let want = context.get(index).type_id;
                        self.state.check_assignable(self.state.infer_with_expected(pair.1, want), want, f"tuple element {index}", pair.1); fields.push((pair.0, want));
                    } else { fields.push((pair.0, self.state.infer_expr(pair.1))); }
                }
                return self.state.type_table.make_tuple(fields);
            case .array_literal(let data): return self.array(data);
            case .dict_literal(let data): return self.dict(data);
            case .lambda(let data): return self.lambda_expr(id, data);
            case .switch_expr(let data): return self.switch_expr(id, data);
            case .struct_literal(let data): return self.struct_literal(data);
            case .cast(let data): return self.cast(id, data);
            case .type_check(let data): self.state.infer_expr(data.expr); return self.state.builtin("Bool");
            case .try_expr(let data): return self.propagate(id, self.state.infer_expr(data.value), "?");
            case .size_of_expr(let data): return self.intrinsic(id, data.type_arg, "size");
            case .type_id_expr(let data): return self.intrinsic(id, data.type_arg, "type");
            case .align_of_expr(let data): return self.intrinsic(id, data.type_arg, "align");
            case .drop_of_expr(let data): return self.intrinsic(id, data.type_arg, "drop");
            case .clone_of_expr(let data): return self.intrinsic(id, data.type_arg, "clone");
            case .optional_chain(let data): return self.optional_chain(id, data);
            default: return self.state.type_table.error_type;
        }
    }
    def literal(id: NodeId, data: LiteralAst) -> TypeId {
        switch data.kind {
            case "int": return self.integer(id, data, false);
            case "float":
                if let context = self.state.expected_type { let type = self.state.type_table.get_optional_inner(context) ?? context; if self.state.type_table.is_float(type) { return type; } }
                return self.state.builtin("f64");
            case "bool": return self.state.builtin("Bool");
            case "char": return self.state.builtin("i32");
            case "nil": return self.state.type_table.nil_type;
            case "string": if let symbol = self.state.symbol_table.get_type_symbol("String") { return self.state.type_table.make_struct(symbol); }
            default: {}
        }
        self.state.type_table.error_type
    }
    def fits(value: String, negative: Bool, type: TypeId) -> Bool {
        let width = integer_width(self.state.type_table, type);
        let signed = self.state.type_table.is_signed_integer(type);
        if width == 0 || negative && !signed && !value.equals("0") { return false; }
        var limit = "";
        if signed {
            switch width {
                case 8: if negative { limit = "128"; } else { limit = "127"; }
                case 16: if negative { limit = "32768"; } else { limit = "32767"; }
                case 32: if negative { limit = "2147483648"; } else { limit = "2147483647"; }
                case 64: if negative { limit = "9223372036854775808"; } else { limit = "9223372036854775807"; }
                default: return false;
            }
        } else { switch width { case 8: limit = "255"; case 16: limit = "65535"; case 32: limit = "4294967295"; case 64: limit = "18446744073709551615"; default: return false; } }
        if value.len() != limit.len() { return value.len() < limit.len(); }
        for i in 0..<(value.len() as i32) { if value.char_at(i) != limit.char_at(i) { return value.char_at(i) < limit.char_at(i); } }
        true
    }
    def integer(id: NodeId, data: LiteralAst, negative: Bool) -> TypeId {
        var value = "0"; switch data.value { case .integer(let text): value = text; default: {} }
        var display = value; if negative && !value.equals("0") { display = "-" + value; }
        if let context = self.state.expected_type {
            var type = context;
            if let inner = self.state.type_table.get_optional_inner(type) { if self.state.type_table.is_numeric(inner) { type = inner; } }
            if self.state.type_table.is_integer(type) {
                if !self.fits(value, negative, type) { self.state.error(TypeErrorKind.type_mismatch(), f"Integer literal {display} does not fit in {self.state.type_table.format_type(type)}", id); }
                return type;
            }
            if self.state.type_table.is_float(type) { return type; }
        }
        for name in ["i32", "i64", "u64"] { let type = self.state.builtin(name); if self.fits(value, negative, type) { return type; } }
        self.state.error(TypeErrorKind.type_mismatch(), f"Integer literal {display} exceeds the range of every built-in integer type", id);
        self.state.builtin("i64")
    }
    def identifier(id: NodeId) -> TypeId {
        if let sid = self.state.node_symbols[id.id] {
            if let type = self.state.type_env[sid.id] { return type; }
            if let constant = self.state.constant_decl(sid) { return self.state.constant_type(sid, constant); }
            if let symbol = self.state.symbol_table.get_symbol(sid) {
                switch symbol.kind {
                    case .function | .extern_func: return self.state.generic_inference.get_function_type(symbol);
                    case .struct_type: return self.state.type_table.make_struct(sid);
                    case .enum_type: return self.state.type_table.make_enum(sid);
                    case .type_alias:
                        if let ref = symbol.decl_node { if let node = self.state.arena.get(ref) { switch node.form { case .type_alias_decl(let data): return self.state.resolve_type(data.aliased_type); default: {} } } }
                    case .enum_case: return self.state.enum_case_type(symbol);
                    default: {}
                }
            }
        }
        self.state.type_table.error_type
    }
    def binary(id: NodeId, data: BinaryOpAst) -> TypeId {
        if data.op.equals("??") {
            let left = self.state.infer_with_expected(data.left, nil);
            guard let inner = self.state.type_table.get_optional_inner(left) else {
                self.state.error(TypeErrorKind.invalid_operation(), "left operand of ?? must be optional", id); return self.state.type_table.error_type;
            }
            let right = self.state.infer_with_expected(data.right, inner);
            if self.state.type_table.is_optional(right) || right == self.state.type_table.nil_type {
                self.state.check_assignable(right, left, "coalescing fallback", data.right); return left;
            }
            self.state.check_assignable(right, inner, "coalescing fallback", data.right); return inner;
        }
        let left = self.state.infer_expr(data.left); let right = self.state.infer_expr(data.right);
        if is_equality_op(data.op) {
            // `x == nil` and `x != nil` test whether an optional holds a value.
            let table = self.state.type_table;
            if (left == table.nil_type && table.is_optional(right)) || (right == table.nil_type && table.is_optional(left)) { return self.state.builtin("Bool"); }
            // With an optional operand, equal means both nil or both present with equal values.
            if (table.is_optional(left) || table.is_optional(right)) && left != table.nil_type && right != table.nil_type {
                let inner_left = table.get_optional_inner(left) ?? left; let inner_right = table.get_optional_inner(right) ?? right;
                self.state.result.optional_comparisons[id.id] = true;
                if let type = self.state.try_operator_overload(id, inner_left, data.op, inner_right) { return type; }
                self.state.binary_types(inner_left, data.op, inner_right);
                return self.state.builtin("Bool");
            }
        }
        if let type = self.state.try_operator_overload(id, left, data.op, right) { return type; }
        self.state.binary_types(left, data.op, right)
    }
    def unary(id: NodeId, data: UnaryOpAst) -> TypeId {
        if data.op.equals("spawn") {
            guard let operand = data.operand else { return self.state.type_table.error_type; }
            var is_call = false;
            if let node = self.state.arena.get(operand) { switch node.form { case .call: is_call = true; default: {} } }
            if !is_call { self.state.error(TypeErrorKind.invalid_operation(), "'spawn' requires an async function call"); return self.state.type_table.error_type; }
            let old = self.spawn_call; self.spawn_call = operand;
            let result = self.state.infer_with_expected(operand, nil); self.spawn_call = old;
            var async = false;
            if let node = self.state.arena.get(operand) { switch node.form { case .call(let call): if let callee = call.callee { if let type = self.state.result.expr_types[callee.id] { if let func = self.state.type_table.get_function_data(type) { async = func.is_async; } } } default: {} } }
            if !async { self.state.error(TypeErrorKind.invalid_operation(), "'spawn' requires an async function call"); return self.state.type_table.error_type; }
            if let task = self.state.type_resolver.lookup_named_struct("Task") { let args = Vec<TypeId>.new(); args.push(result); return self.state.type_table.make_struct(task, args); }
            self.state.error(TypeErrorKind.invalid_operation(), "Import std.task to use 'spawn'"); return self.state.type_table.error_type;
        }
        if data.op.equals("-") { if let operand = data.operand { if let node = self.state.arena.get(operand) { switch node.form { case .literal(let lit): if lit.kind.equals("int") { let type = self.integer(operand, lit, true); self.state.result.expr_types[operand.id] = type; return type; } default: {} } } } }
        let type = self.state.infer_expr(data.operand);
        if let result = self.state.try_unary_overload(id, type, data.op) { return result; }
        switch data.op {
            case "-": if self.state.type_table.is_numeric(type) { return type; } self.state.error(TypeErrorKind.invalid_operation(), f"Cannot negate {self.state.type_table.format_type(type)}");
            case "+": if self.state.type_table.is_numeric(type) { return type; } self.state.error(TypeErrorKind.invalid_operation(), f"Cannot apply unary '+' to {self.state.type_table.format_type(type)}");
            case "!": self.state.check_boolean(type, "operand of !"); return self.state.builtin("Bool");
            case "~": if self.state.type_table.is_integer(type) { return type; } self.state.error(TypeErrorKind.invalid_operation(), "Bitwise not requires integer operand");
            case "await":
                if !self.state.in_async_function { self.state.error(TypeErrorKind.invalid_operation(), "'await' can only be used inside an async function"); return self.state.type_table.error_type; }
                if let info = self.state.type_table.get_type(type) { switch info.data {
                    case .struct_type(let value): if let sid = value.symbol_id { if let sym = self.state.symbol_table.get_symbol(sid) { if sym.name.equals("Task") && value.type_args.len() == 1 { return value.type_args.get(0); } } }
                    default: {}
                } }
                if let func = self.state.type_table.get_function_data(type) { if func.is_async { return func.return_type; } self.state.error(TypeErrorKind.invalid_operation(), "'await' can only be used on async functions"); return self.state.type_table.error_type; }
                return type;
            case "try": return self.propagate(id, type, "try");
            default: return type;
        }
        self.state.type_table.error_type
    }
    def ternary(data: TernaryOpAst) -> TypeId {
        if let cond = data.condition { self.state.check_boolean(self.state.infer_expr(cond), "ternary condition"); }
        let a = self.state.infer_expr(data.then_expr); let b = self.state.infer_expr(data.else_expr);
        if a == b { return a; }
        if self.state.type_table.can_widen_int(a, b) { return b; } if self.state.type_table.can_widen_int(b, a) { return a; }
        if let inner = self.state.type_table.get_optional_inner(a) { if !self.state.type_table.is_optional(b) && self.state.types_equal(inner, b) { return a; } }
        if let inner = self.state.type_table.get_optional_inner(b) { if !self.state.type_table.is_optional(a) && self.state.types_equal(inner, a) { return b; } }
        // A contextual type both branches fit, or `nil` against a value making it optional.
        if let want = self.state.expected_type { if self.converts_to(a, want) && self.converts_to(b, want) { return want; } }
        let table = self.state.type_table;
        if a == table.nil_type && !table.is_optional(b) && !table.is_error(b) { return table.make_optional(b); }
        if b == table.nil_type && !table.is_optional(a) && !table.is_error(a) { return table.make_optional(a); }
        self.state.error(TypeErrorKind.type_mismatch(), f"Ternary branches have incompatible types: '{self.state.type_table.format_type(a)}' vs '{self.state.type_table.format_type(b)}'"); a
    }
    // Whether a value of `source` converts implicitly to `target` (equal, widened or wrapped).
    def converts_to(source: TypeId, target: TypeId) -> Bool {
        let table = self.state.type_table;
        if self.state.types_equal(source, target) || table.can_widen_int(source, target) { return true; }
        if let inner = table.get_optional_inner(target) { return source == table.nil_type || self.converts_to(source, inner); }
        false
    }
    def argument(id: NodeId) -> ArgumentAst? { if let node = self.state.arena.get(id) { switch node.form { case .argument(let data): return data; default: {} } } nil }
    def decl_params(sid: SymbolId?) -> Vec<NodeId>? {
        if let ref = sid { if let sym = self.state.symbol_table.get_symbol(ref) { if let id = sym.decl_node { if let node = self.state.arena.get(id) { switch node.form { case .func_decl(let data): return data.params; case .extern_func_decl(let data): return data.params; default: {} } } } } } nil
    }
    def call(id: NodeId, data: CallAst) -> TypeId {
        let old = self.state.expected_type; self.state.expected_type = nil;
        defer { self.state.expected_type = old; }
        guard let callee = data.callee else { return self.state.type_table.error_type; }
        let prev = self.callee; self.callee = callee;
        let type = self.state.infer_expr(callee); self.callee = prev;
        if let func = self.state.type_table.get_function_data(type) {
            var symbol = self.state.node_symbols[callee.id];
            if let found = symbol {} else { symbol = self.state.result.member_method_symbols[callee.id]; }
            let mapping = Dict<String, TypeId>.with_capacity(16, 1);
            if let sid = symbol {
                if let sym = self.state.symbol_table.get_symbol(sid) { if let decl = sym.decl_node { if let node = self.state.arena.get(decl) { switch node.form {
                    case .extern_func_decl(let value): self.state.require_unsafe(f"calling external '{value.abi}' function", id);
                    case .func_decl(let value): if value.is_unsafe { self.state.require_unsafe(f"calling `unsafe def {value.name}`", id); }
                    default: {}
                } } } }
                for pair in self.state.generic_inference.infer_generic_call_args(sid, id, old).entries() { mapping[pair.key] = pair.value; }
                if let node = self.state.arena.get(callee) { switch node.form { case .member_access(let member): if self.is_type_reference(member.object) {
                    for pair in self.owner_generics(sid, data, old).entries() { mapping[pair.key] = pair.value; }
                    if mapping.len() > 0 { self.update_receiver(member.object, mapping); }
                } default: {} } }
            }
            var is_spawn = false; if let task_call = self.spawn_call { is_spawn = task_call == id; }
            if func.is_async && !self.state.in_async_function && !is_spawn {
                var name = "<async function>"; if let sid = symbol { if let sym = self.state.symbol_table.get_symbol(sid) { if !sym.name.is_empty() { name = "'" + sym.name + "'"; } } }
                self.state.error(TypeErrorKind.invalid_operation(), f"async function {name} can only be called from an async function; mark the enclosing function 'async' or use 'await' inside an async context");
            }
            let params = self.decl_params(symbol); let count = func.params.len(); var min = count;
            if let decl = params { while min > 0 { if let param = self.state.param(decl[min - 1]) { if let default_value = param.default_value { min -= 1; continue; } } break; } }
            let argc = data.arguments.len();
            if argc > count || argc < min {
                var message = f"Expected {count} arguments, got {argc}";
                if min != count { message = f"Expected between {min} and {count} arguments, got {argc}"; }
                self.state.error(TypeErrorKind.wrong_arg_count(), message, id);
            } else {
                if let decl = params { for index in 0..<argc { if let arg = self.argument(data.arguments[index]) { if let param = self.state.param(decl[index]) {
                    var matches = false;
                    if let expected = param.external_name { if let actual = arg.label { matches = expected.equals(actual); } }
                    else { if let actual = arg.label { matches = actual.equals(param.internal_name); } else { matches = true; } }
                    if !matches { self.state.error(TypeErrorKind.wrong_arg_type(), f"argument {index + 1} label mismatch: expected {param.external_name ?? "<none>"}, got {arg.label ?? "<none>"}", data.arguments[index]); }
                } } } }
                if let sid = symbol { self.check_call_constraints(sid, mapping, id); }
                if let names = self.requirement_generics(callee) {
                    // Generic protocol requirement called through a constrained type parameter:
                    // infer the method's own type parameters from the arguments.
                    for index in 0..<argc { if let arg = self.argument(data.arguments[index]) { if let value = arg.value {
                        let pattern = func.params.get(index);
                        infer_resolved_type_arguments(self.state.type_table, pattern, self.state.infer_with_expected(value, pattern), names, mapping);
                    } } }
                }
                for index in 0..<argc { if let arg = self.argument(data.arguments[index]) { if let value = arg.value {
                    let expected = self.state.generic_inference.substitute_type(func.params.get(index), mapping);
                    self.state.check_assignable(self.state.infer_with_expected(value, expected), expected, f"argument {index + 1}");
                } } }
            }
            self.state.record_call(id, CalleeKind.static_call(), symbol);
            return self.state.generic_inference.substitute_type(func.return_type, mapping);
        }
        if let node = self.state.arena.get(callee) { switch node.form { case .member_access(let member): if let case_def = self.state.lookup_enum_case(type, member.member) {
            let instantiated = self.enum_args(type, case_def, data.arguments, old);
            self.state.record_call(id, CalleeKind.enum_ctor(), nil, member.member); return instantiated;
        } default: {} } }
        self.state.error(TypeErrorKind.not_callable(), f"Cannot call {self.state.type_table.format_type(type)}"); self.state.type_table.error_type
    }
    def enum_args(type: TypeId, case_def: EnumCaseDefAst, args: Vec<NodeId>, expected: TypeId?) -> TypeId {
        if args.len() != case_def.payload.len() { self.state.error(TypeErrorKind.wrong_arg_count(), f"Enum case '{case_def.name}' expects {case_def.payload.len()} payload value(s), got {args.len()}"); return type; }
        let mapping = Dict<String, TypeId>.with_capacity(16, 1); var names = Dict<String, Bool>.with_capacity(16, 1);
        let decl = self.state.enum_decl(type);
        if let data = decl {
            names = self.state.generic_names(data.generic_params);
            if let info = self.state.type_table.get_type(type) { switch info.data { case .enum_type(let value):
                self.seed(data.generic_params, value.type_args, mapping, false);
                if let exp = expected { if let hint = self.state.type_table.get_type(exp) { switch hint.data { case .enum_type(let other): if other.symbol_id == value.symbol_id { self.seed(data.generic_params, other.type_args, mapping, true); } default: {} } } }
                default: {}
            } }
        }
        for index in 0..<args.len() { if let arg = self.argument(args[index]) { if let value = arg.value { let arg_type = self.state.infer_expr(value); self.state.generic_inference.infer_type_node_generics(case_def.payload[index].1, arg_type, names, mapping); } } }
        for index in 0..<args.len() { if let arg = self.argument(args[index]) { if let value = arg.value {
            let expected = self.state.generic_inference.substitute_type(self.state.resolve_type(case_def.payload[index].1), mapping);
            self.state.check_assignable(self.state.infer_with_expected(value, expected), expected, f"enum payload {index + 1}");
        } } }
        if let data = decl { if data.generic_params.len() > 0 {
            let missing = self.unbound(data.generic_params, mapping);
            if missing.len() > 0 { self.state.error(TypeErrorKind.cannot_infer(), f"Cannot infer type parameter(s) {join_strings(missing, ", ")} of enum '{data.name}.{case_def.name}' from arguments; add a type annotation to the binding"); return type; }
            self.state.generic_inference.check_generic_constraints(mapping, data.generic_params, self.state.conformance_checker);
            if let info = self.state.type_table.get_type(type) { switch info.data { case .enum_type(let value): return self.state.type_table.make_enum(value.symbol_id, self.type_args(data.generic_params, mapping)); default: {} } }
        } }
        type
    }
    def seed(params: Vec<NodeId>, args: FrozenVec<TypeId>, mapping: Dict<String, TypeId>, only_missing: Bool) -> Void {
        if params.len() != args.len() { return; }
        for index in 0..<params.len() { let name = self.state.generic_name(params[index]); if !only_missing || !mapping.contains(name) { mapping[name] = args.get(index); } }
    }
    def unbound(params: Vec<NodeId>, mapping: Dict<String, TypeId>) -> Vec<String> { let out = Vec<String>.new(); for p in params { let name = self.state.generic_name(p); if !mapping.contains(name) { out.push(name); } } out }
    def type_args(params: Vec<NodeId>, mapping: Dict<String, TypeId>) -> Vec<TypeId> { let out = Vec<TypeId>.new(); for p in params { out.push(mapping[self.state.generic_name(p)] ?? self.state.type_table.error_type); } out }
    def is_type_reference(id: NodeId?) -> Bool {
        if let ref = id {
            if let node = self.state.arena.get(ref) { switch node.form { case .type_reference: return true; default: {} } }
            if let sid = self.state.node_symbols[ref.id] { if let symbol = self.state.symbol_table.get_symbol(sid) { switch symbol.kind { case .struct_type | .enum_type | .builtin_type | .type_alias: return true; default: {} } } }
        }
        false
    }
    def member_parts(id: NodeId?) -> Vec<String>? {
        if let ref = id { if let node = self.state.arena.get(ref) { switch node.form {
            case .identifier(let data): let out = Vec<String>.new(); out.push(data.name); return out;
            case .member_access(let data): if let out = self.member_parts(data.object) { out.push(data.member); return out; }
            default: {}
        } } } nil
    }
    // Generic calls must satisfy the callee's bounds and `where` equality constraints.
    def check_call_constraints(sid: SymbolId, mapping: Dict<String, TypeId>, id: NodeId) -> Void {
        guard let symbol = self.state.symbol_table.get_symbol(sid) else { return; }
        guard let decl = symbol.decl_node else { return; }
        guard let node = self.state.arena.get(decl) else { return; }
        var func: FuncDeclAst? = nil; switch node.form { case .func_decl(let data): func = data; default: {} }
        guard let data = func else { return; }
        if data.generic_params.len() == 0 { return; }
        if self.unbound(data.generic_params, mapping).len() > 0 { return; }
        self.state.generic_inference.check_generic_constraints(mapping, data.generic_params, self.state.conformance_checker);
        for pair in self.state.equality_constraints(data.constraints) {
            let actual = self.state.generic_inference.substitute_type(pair.0, mapping); let expected = self.state.generic_inference.substitute_type(pair.1, mapping);
            if self.state.type_table.has_type_variables(actual) || self.state.type_table.has_type_variables(expected) { continue; }
            if !self.state.types_equal(actual, expected) {
                self.state.error(TypeErrorKind.type_mismatch(), f"Call to '{data.name}' requires {self.state.type_table.format_type(pair.0)} == {self.state.type_table.format_type(pair.1)}, but it is {self.state.type_table.format_type(actual)}", id);
            }
        }
    }
    // Generic parameter names of the protocol requirement named by `callee` when its receiver
    // is a protocol-constrained type parameter.
    def requirement_generics(callee: NodeId) -> Dict<String, Bool>? {
        guard let node = self.state.arena.get(callee) else { return nil; }
        var access: MemberAccessAst? = nil; switch node.form { case .member_access(let value): access = value; default: {} }
        guard let member = access else { return nil; }
        guard let object = member.object else { return nil; }
        guard let receiver = self.state.result.expr_types[object.id] else { return nil; }
        guard let info = self.state.type_table.get_type(receiver) else { return nil; }
        switch info.data { case .type_variable(let variable):
            for bound in variable.bounds { if let protocol = self.state.type_table.get_type(bound) { switch protocol.data { case .protocol(let data):
                for func in data.func_requirements { if func.name.equals(member.member) && func.generic_params.len() > 0 {
                    let names = Dict<String, Bool>.with_capacity(4, 1); for name in func.generic_params { names[name] = true; } return names;
                } }
                default: {}
            } } }
            default: {}
        }
        nil
    }
    // A requirement seen through the type parameter `C` refers to C's associated types:
    // `Item` becomes the projection `C.Item` (or its `where` equality).
    def project_member(member: TypeId, receiver: String, protocol: TypeId) -> TypeId {
        guard let info = self.state.type_table.get_type(protocol) else { return member; }
        var symbol: SymbolId? = nil; switch info.data { case .protocol(let data): symbol = data.symbol_id; default: {} }
        guard let sid = symbol else { return member; }
        let names = self.state.conformance_checker.associated_names(sid);
        if names.len() == 0 { return member; }
        let mapping = Dict<String, TypeId>.with_capacity(4, 1);
        for name in names { mapping[name] = self.state.type_table.make_type_variable(receiver + "." + name); }
        self.state.with_equalities(self.state.generic_inference.substitute_type(member, mapping))
    }
    def protocol_member(protocol: TypeId, name: String, existential: Bool) -> TypeId? {
        if let info = self.state.type_table.get_type(protocol) { switch info.data { case .protocol(let data):
            for func in data.func_requirements { if func.name.equals(name) { return self.state.type_table.make_function(func.params.to_vec(), func.return_type, !existential && func.is_async); } }
            for prop in data.prop_requirements { if prop.name.equals(name) { return prop.type_id; } }
            default: {}
        } } nil
    }
    def member(id: NodeId, data: MemberAccessAst) -> TypeId {
        if let parts = self.member_parts(id) { if let sid = self.state.resolution.imported_symbols[join_strings(parts, ".")] {
            if let sym = self.state.symbol_table.get_symbol(sid) { switch sym.kind {
                case .function | .type_alias | .struct_type | .enum_type:
                    // Qualified accesses already carry resolver identities.
                    return self.identifier(id);
                default: {}
            } } return self.state.type_table.error_type;
        } }
        let type = self.state.infer_with_expected(data.object, nil); let object_is_type = self.is_type_reference(data.object);
        if let info = self.state.type_table.get_type(type) { switch info.data {
            case .existential(let value): if let member = self.protocol_member(value.protocol_id, data.member, true) {
                // Through `any P` the concrete type is unknown, so a member must not depend on
                // unfixed associated types (fix them with `any P<...>`) or on its own generics.
                if self.state.type_table.has_type_variables(member) {
                    let protocol = self.state.type_table.format_type(value.protocol_id);
                    self.state.error(TypeErrorKind.invalid_operation(), f"'{data.member}' cannot be used through any {protocol}: its signature {self.state.type_table.format_type(member)} depends on associated or generic types; fix the associated types with any {protocol}<...>", id);
                    return self.state.type_table.error_type;
                }
                return member;
            }
            case .type_variable(let value): for bound in value.bounds { if let member = self.protocol_member(bound, data.member, false) { return self.project_member(member, value.name, bound); } }
            default: {}
        } }
        if !object_is_type { if let field = self.state.member_resolver.get_field(type, data.member) { self.field_visibility(field, id); self.state.record_call(id, CalleeKind.indirect()); return field.type_id; } }
        if let method = self.state.member_resolver.get_method(type, data.member, object_is_type) {
            self.state.result.member_method_symbols[id.id] = method.symbol_id;
            var called = false; if let callee = self.callee { called = callee == id; }
            if !called && !object_is_type { return self.method_value(id, data, method); }
            return method.signature;
        }
        if object_is_type { if let info = self.state.type_table.get_type(type) { switch info.data { case .enum_type:
            if let case_def = self.state.lookup_enum_case(type, data.member) { if case_def.payload.len() == 0 {
                self.state.record_call(id, CalleeKind.enum_ctor(), nil, data.member);
                var called = false; if let callee = self.callee { called = callee == id; }
                if !called { return self.enum_args(type, case_def, Vec<NodeId>.new(), self.state.expected_type); }
            } }
            return type;
            default: {}
        } } }
        self.state.error(TypeErrorKind.undefined_member(), f"Type {self.state.type_table.format_type(type)} has no member '{data.member}'", id); self.state.type_table.error_type
    }
    def field_visibility(field: FieldInfo, id: NodeId) -> Void {
        if field.visibility.equals("pub") { return; }
        if let module = field.source_module { if let current = self.state.member_resolver.get_current_source_module() { if !module.equals(current) { self.state.error(TypeErrorKind.invalid_operation(), f"field '{field.name}' is not accessible from outside module '{module}' (mark it `pub` to expose it)", id); } } }
    }
    def symbol_name(id: SymbolId?) -> String { if let sid = id { if let sym = self.state.symbol_table.get_symbol(sid) { return sym.name; } } "" }
    def subscript_expr(id: NodeId, data: SubscriptAst) -> TypeId {
        let type = self.state.infer_expr(data.object);
        let indices = Vec<TypeId>.new(); for index in data.indices { indices.push(self.state.infer_with_expected(index, nil)); }
        if let info = self.state.type_table.get_type(type) { switch info.data { case .struct_type(let value):
            let name = self.symbol_name(value.symbol_id);
            if data.indices.len() == 1 && (name.equals("Vec") || name.equals("String")) {
                if let index = self.state.type_table.get_type(indices[0]) { switch index.data { case .struct_type(let range): if self.symbol_name(range.symbol_id).equals("IndexRange") {
                    var span: Span? = nil; if let node = self.state.arena.get(id) { span = node.span; }
                    let member = self.state.arena.add(NodeForm.member_access(MemberAccessAst { object: data.object, member: "slice" }), span);
                    let arg = self.state.arena.add(NodeForm.argument(ArgumentAst { label: nil, value: data.indices[0] }), span);
                    let args = Vec<NodeId>.new(); args.push(arg);
                    let call = self.state.arena.add(NodeForm.call(CallAst { callee: member, arguments: args, is_interpolation: false }), span);
                    self.state.lowered_expressions[id.id] = call; return self.infer_expr(call);
                } default: {} } }
            }
            if let symbol = value.symbol_id {} else { if data.indices.len() == 1 { if let node = self.state.arena.get(data.indices[0]) { switch node.form { case .literal(let lit): switch lit.value { case .integer(let text):
                let fields = value.anon_fields ?? FrozenVec<TupleField>.empty();
                for index in 0..<fields.len() { if text.equals(index.to_string()) { return fields.get(index).type_id; } }
                default: {}
            } default: {} } } } }
            if name.equals("Vec") && value.type_args.len() == 1 { return value.type_args.get(0); }
            if name.equals("Dict") && value.type_args.len() == 2 { return self.state.type_table.make_optional(value.type_args.get(1)); }
            if let method = self.state.member_resolver.get_method(type, "__get__") { if let func = self.state.type_table.get_function_data(method.signature) {
                self.state.check_subscript_indices(func, data.indices, 0, "__get__", id); return func.return_type;
            } }
            // A set-only subscript is still a valid assignment target.
            if let method = self.state.member_resolver.get_method(type, "__set__") { if let func = self.state.type_table.get_function_data(method.signature) {
                if func.params.len() > 0 { return func.params.get(func.params.len() - 1); }
            } }
            default: {}
        } }
        self.state.error(TypeErrorKind.type_mismatch(), f"Type {self.state.type_table.format_type(type)} does not support subscripting", id); self.state.type_table.error_type
    }
    // Type arguments of the contextual Vec/Dict type, looking through one optional layer.
    def expected_collection_args(name: String, count: i32) -> FrozenVec<TypeId>? {
        guard let expected = self.state.expected_type else { return nil; }
        let type = self.state.type_table.get_optional_inner(expected) ?? expected;
        if let info = self.state.type_table.get_type(type) { switch info.data {
            case .struct_type(let value): if self.symbol_name(value.symbol_id).equals(name) && value.type_args.len() == count { return value.type_args; }
            default: {}
        } }
        nil
    }
    def array(data: ArrayLiteralAst) -> TypeId {
        if let args = self.expected_collection_args("Vec", 1) {
            let element = args.get(0);
            for index in 0..<data.elements.len() { let value = data.elements[index]; self.state.check_assignable(self.state.infer_with_expected(value, element), element, f"Vec element {index}", value); }
            return self.state.type_resolver.make_vec_type(element);
        }
        if data.elements.len() == 0 {
            self.state.error(TypeErrorKind.cannot_infer(), "Cannot infer the element type of an empty Vec literal; add a type annotation");
            return self.state.type_table.error_type;
        }
        let type = self.state.infer_expr(data.elements[0]);
        for index in 1..<data.elements.len() { let other = self.state.infer_expr(data.elements[index]); if !self.state.types_equal(type, other) && !self.state.type_table.is_error(other) { self.state.error(TypeErrorKind.type_mismatch(), f"Vec element at index {index} has type {self.state.type_table.format_type(other)}, expected {self.state.type_table.format_type(type)}"); } }
        self.state.type_resolver.make_vec_type(type)
    }
    def dict(data: DictLiteralAst) -> TypeId {
        if let args = self.expected_collection_args("Dict", 2) {
            let key = args.get(0); let value = args.get(1);
            for index in 0..<data.entries.len() { let entry = data.entries[index];
                self.state.check_assignable(self.state.infer_with_expected(entry.0, key), key, f"Dict key {index}", entry.0);
                self.state.check_assignable(self.state.infer_with_expected(entry.1, value), value, f"Dict value {index}", entry.1);
            }
            return self.state.type_resolver.make_dict_type(key, value);
        }
        if data.entries.len() == 0 {
            self.state.error(TypeErrorKind.cannot_infer(), "Cannot infer the key and value types of an empty Dict literal; add a type annotation");
            return self.state.type_table.error_type;
        }
        let key = self.state.infer_expr(data.entries[0].0); let value = self.state.infer_expr(data.entries[0].1);
        for index in 1..<data.entries.len() {
            let k = self.state.infer_expr(data.entries[index].0); let v = self.state.infer_expr(data.entries[index].1);
            if !self.state.types_equal(key, k) && !self.state.type_table.is_error(k) { self.state.error(TypeErrorKind.type_mismatch(), f"Dictionary key at index {index} has inconsistent type"); }
            if !self.state.types_equal(value, v) && !self.state.type_table.is_error(v) { self.state.error(TypeErrorKind.type_mismatch(), f"Dictionary value at index {index} has inconsistent type"); }
        }
        self.state.type_resolver.make_dict_type(key, value)
    }
    def block_return(stmts: Vec<NodeId>) -> TypeId {
        for id in stmts { if let node = self.state.arena.get(id) { switch node.form {
            case .return_stmt(let data): if let value = data.value { if let type = self.state.result.expr_types[value.id] { return type; } }
            case .if_stmt(let data):
                let type = self.block_return(self.state.block_statements(data.then_block)); if !self.state.type_table.is_error(type) { return type; }
                if let block = data.else_block { let other = self.block_return(self.state.block_statements(block)); if !self.state.type_table.is_error(other) { return other; } }
            case .switch_stmt(let data): for branch in data.cases { if let child = self.state.arena.get(branch) { switch child.form { case .switch_case(let case_data): let type = self.block_return(case_data.body); if !self.state.type_table.is_error(type) { return type; } default: {} } } }
            default: {}
        } } }
        self.state.type_table.void_type
    }
    def lambda_expr(id: NodeId, data: LambdaAst) -> TypeId {
        var context: FunctionTypeData? = nil; if let expected = self.state.expected_type { context = self.state.type_table.get_function_data(self.state.type_table.get_optional_inner(expected) ?? expected); }
        if let pinned = self.state.synthetic_lambda_types[id.id] { context = self.state.type_table.get_function_data(pinned); }
        let params = Vec<TypeId>.new();
        for index in 0..<data.params.len() { let pair = data.params[index]; var type = self.state.type_table.error_type;
            if let annotation = pair.1 { type = self.state.resolve_type(annotation); }
            else { var inferred = false; if let func = context { if index < func.params.len() { type = func.params.get(index); inferred = true; } } if !inferred { self.state.error(TypeErrorKind.type_mismatch(), "Cannot infer lambda parameter type; add an annotation or a function type context", pair.0); } }
            params.push(type); self.state.bind_pattern(pair.0, type);
        }
        let old_return = self.state.current_function_return; let old_expected = self.state.expected_type;
        let old_unsafe = self.state.in_unsafe; let old_async = self.state.in_async_function;
        var expected_return: TypeId? = nil; if let func = context { if !self.state.type_table.has_type_variables(func.return_type) { expected_return = func.return_type; } }
        if let declared = data.return_type { expected_return = self.state.resolve_type(declared); }
        self.state.current_function_return = expected_return; self.state.expected_type = nil; self.state.in_unsafe = false; self.state.in_async_function = false;
        defer { self.state.current_function_return = old_return; self.state.expected_type = old_expected; self.state.in_unsafe = old_unsafe; self.state.in_async_function = old_async; }
        for stmt in data.body { self.state.check_stmt(stmt); }
        let ret = expected_return ?? self.block_return(data.body);
        if ret != self.state.type_table.void_type && !self.state.definitely_returns(data.body) { self.state.error(TypeErrorKind.type_mismatch(), "lambda must return a value on all paths", id); }
        self.state.type_table.make_function(params, ret)
    }
    def coverage(id: NodeId, type: TypeId) -> Void {
        let errors = self.state.result.errors;
        ExhaustivenessChecker.new(self.state.arena, self.state.type_table, self.state.symbol_table, (kind: TypeErrorKind, message: String) -> { errors.push(TypeError { kind, message, span: nil }); }).check_switch(id, type);
    }
    def switch_expr(id: NodeId, data: SwitchExprAst) -> TypeId {
        var result = self.state.expected_type; let type = self.state.infer_with_expected(data.value, nil);
        for branch in data.cases { if let node = self.state.arena.get(branch) { switch node.form { case .switch_case(let case_data):
            for pair in case_data.patterns { self.state.bind_pattern(pair.0, type); if let guard_expr = pair.1 { self.state.check_boolean(self.state.infer_with_expected(guard_expr, nil), "case guard"); } }
            if case_data.body.len() > 0 { if let stmt = self.state.arena.get(case_data.body[0]) { switch stmt.form { case .expr_stmt(let expr):
                let inferred = self.state.infer_with_expected(expr.expr, result);
                if let expected = result { self.state.check_assignable(inferred, expected, "switch expression branch", expr.expr); } else { result = inferred; }
                default: {}
            } } }
            default: {}
        } } }
        self.coverage(id, type);
        if let ret = result { if ret != self.state.type_table.void_type { return ret; } }
        self.state.error(TypeErrorKind.type_mismatch(), "switch expression branches must produce a value", id); self.state.type_table.error_type
    }
    def owner_generics(sid: SymbolId, call: CallAst, expected: TypeId?) -> Dict<String, TypeId> {
        let mapping = Dict<String, TypeId>.with_capacity(16, 1);
        guard let symbol = self.state.symbol_table.get_symbol(sid) else { return mapping; }
        guard let func = self.state.function(symbol.decl_node) else { return mapping; }
        var generics = Vec<NodeId>.new();
        for candidate in self.state.symbol_table.symbols.values() {
            if let ref = candidate.decl_node { if let node = self.state.arena.get(ref) {
                var members = Vec<NodeId>.new(); var params = Vec<NodeId>.new();
                switch node.form { case .struct_decl(let data): members = data.members; params = data.generic_params; case .enum_decl(let data): members = data.members; params = data.generic_params; case .extension_decl(let data): members = data.members; params = data.generic_params; default: {} }
                var found = false; for member in members { if let decl = symbol.decl_node { if decl == member { found = true; } } }
                if found { generics = params; break; }
            } }
        }
        if generics.len() == 0 { return mapping; }
        let names = self.state.generic_names(generics);
        for index in 0..<call.arguments.len() {
            if index >= func.params.len() { break; }
            if let arg = self.argument(call.arguments[index]) { if let value = arg.value { if let param = self.state.param(func.params[index]) {
                let type = self.state.result.expr_types[value.id] ?? self.state.infer_expr(value);
                self.state.generic_inference.infer_type_node_generics(param.type_annotation, type, names, mapping);
            } } }
        }
        if let hint = expected { if let ret = func.return_type { self.state.generic_inference.infer_type_node_generics(ret, hint, names, mapping); } }
        mapping
    }
    def update_receiver(id: NodeId?, mapping: Dict<String, TypeId>) -> Void {
        if let ref = id { if let sid = self.state.node_symbols[ref.id] { if let sym = self.state.symbol_table.get_symbol(sid) { if let decl = sym.decl_node { if let node = self.state.arena.get(decl) { switch node.form {
            case .struct_decl(let data): if data.generic_params.len() > 0 { self.state.result.expr_types[ref.id] = self.state.type_table.make_struct(sid, self.type_args(data.generic_params, mapping)); }
            case .enum_decl(let data): if data.generic_params.len() > 0 { self.state.result.expr_types[ref.id] = self.state.type_table.make_enum(sid, self.type_args(data.generic_params, mapping)); }
            default: {}
        } } } } } }
    }
    def struct_literal(data: StructLiteralAst) -> TypeId {
        let type = self.state.resolve_type(data.type_name);
        guard let info = self.state.type_table.get_type(type) else { return type; }
        var symbol: SymbolId? = nil; var args = FrozenVec<TypeId>.empty(); var is_struct = false;
        switch info.data { case .struct_type(let value): is_struct = true; symbol = value.symbol_id; args = value.type_args; default: {} }
        if !is_struct { for id in data.arguments { if let arg = self.argument(id) { self.state.infer_expr(arg.value); } } return type; }
        var decl: StructDeclAst? = nil;
        if let sid = symbol { if let sym = self.state.symbol_table.get_symbol(sid) { if let ref = sym.decl_node { if let node = self.state.arena.get(ref) { switch node.form { case .struct_decl(let value): decl = value; default: {} } } } } }
        let mapping = Dict<String, TypeId>.with_capacity(16, 1); let annotations = Dict<String, NodeId>.with_capacity(16, 1);
        let fields = Vec<String>.new(); var names = Dict<String, Bool>.with_capacity(16, 1);
        if let value = decl {
            names = self.state.generic_names(value.generic_params);
            if value.generic_params.len() == args.len() { for index in 0..<args.len() {
                let arg = args.get(index); var variable = false; if let arg_info = self.state.type_table.get_type(arg) { switch arg_info.data { case .type_variable: variable = true; default: {} } }
                if !self.state.type_table.is_error(arg) && !variable { mapping[self.state.generic_name(value.generic_params[index])] = arg; }
            } }
            if let expected = self.state.expected_type { if let hint = self.state.type_table.get_type(expected) { switch hint.data { case .struct_type(let exp):
                if let sid = symbol { if let other = exp.symbol_id { if sid == other { self.seed(value.generic_params, exp.type_args, mapping, true); } } }
                default: {}
            } } }
            let defaulted = Dict<String, Bool>.with_capacity(8, 1);
            for member in value.members { if let node = self.state.arena.get(member) { switch node.form { case .property_decl(let prop):
                if let annotation = prop.type_annotation { annotations[prop.name] = annotation; fields.push(prop.name); }
                if let initial = prop.initializer { defaulted[prop.name] = true; }
                default: {}
            } } }
            let seen = Dict<String, Bool>.with_capacity(16, 1);
            for id in data.arguments { if let arg = self.argument(id) { if let label = arg.label {
                if seen.contains(label) { self.state.error(TypeErrorKind.duplicate_member(), f"duplicate field '{label}' in struct literal", id); continue; }
                seen[label] = true;
                if !annotations.contains(label) { self.state.error(TypeErrorKind.undefined_member(), f"struct '{value.name}' has no field '{label}'", id); }
            } } }
            for name in fields { if !seen.contains(name) && !defaulted.contains(name) { self.state.error(TypeErrorKind.type_mismatch(), f"missing field '{name}' in struct literal for '{value.name}'"); } }
        }
        for id in data.arguments { if let arg = self.argument(id) { if let value = arg.value {
            if let label = arg.label {
                var field_expected: TypeId? = nil;
                if let annotation = annotations[label] {
                    let field_type = self.state.generic_inference.substitute_type(self.state.resolve_type(annotation), mapping);
                    if !self.state.type_table.is_error(field_type) && !self.state.type_table.has_type_variables(field_type) { field_expected = field_type; }
                }
                let arg_type = self.state.infer_with_expected(value, field_expected);
                if let annotation = annotations[label] { self.state.generic_inference.infer_type_node_generics(annotation, arg_type, names, mapping); }
            }
            else { self.state.error(TypeErrorKind.type_mismatch(), "Struct literal fields must be labeled", id); }
        } } }
        var result = type;
        if let value = decl { if value.generic_params.len() > 0 {
            let missing = self.unbound(value.generic_params, mapping);
            if missing.len() > 0 { self.state.error(TypeErrorKind.cannot_infer(), f"Cannot infer type parameter(s) {join_strings(missing, ", ")} of struct '{value.name}' from arguments; add explicit type arguments or a type annotation"); }
            else { self.state.generic_inference.check_generic_constraints(mapping, value.generic_params, self.state.conformance_checker); if let sid = symbol { result = self.state.type_table.make_struct(sid, self.type_args(value.generic_params, mapping)); } }
        } }
        for id in data.arguments { if let arg = self.argument(id) { if let value = arg.value {
            let actual = self.state.result.expr_types[value.id] ?? self.state.infer_expr(value);
            if let label = arg.label { if let ann = annotations[label] { self.state.check_assignable(actual, self.state.generic_inference.substitute_type(self.state.resolve_type(ann), mapping), f"field '{label}'"); } }
        } } }
        result
    }
    // `recv.method` used as a value becomes
    // `switch recv { case let __method_receiver: (args) -> { __method_receiver.method(args) } }`,
    // which evaluates the receiver once and binds it into the closure.
    def method_value(id: NodeId, data: MemberAccessAst, method: MethodInfo) -> TypeId {
        guard let func = self.state.type_table.get_function_data(method.signature) else { return method.signature; }
        var span: Span? = nil; if let node = self.state.arena.get(id) { span = node.span; }
        let arena = self.state.arena;
        let receiver_pattern = arena.add(NodeForm.identifier_pattern(IdentifierPatternAst { name: "__method_receiver", binding: "let" }), span);
        let receiver = self.state.symbol_table.create_symbol("__method_receiver", SymbolKind.variable(), Namespace.value()).id;
        self.state.node_symbols[receiver_pattern.id] = receiver;
        let holder = arena.add(NodeForm.identifier(IdentifierAst { name: "__method_receiver" }), span);
        self.state.node_symbols[holder.id] = receiver;
        var labels = Vec<String?>.new();
        if let symbol = self.state.symbol_table.get_symbol(method.symbol_id) { if let decl = symbol.decl_node { if let node = self.state.arena.get(decl) { switch node.form {
            case .func_decl(let decl_data): for param in decl_data.params { if let p = self.state.param(param) { labels.push(p.external_name); } }
            default: {}
        } } } }
        let params = Vec<(NodeId, NodeId?)>.new(); let arguments = Vec<NodeId>.new(); let untyped: NodeId? = nil;
        for index in 0..<func.params.len() {
            let name = f"__method_arg{index}";
            let pattern = arena.add(NodeForm.identifier_pattern(IdentifierPatternAst { name, binding: nil }), span);
            let symbol = self.state.symbol_table.create_symbol(name, SymbolKind.parameter(), Namespace.value()).id;
            self.state.node_symbols[pattern.id] = symbol;
            let value = arena.add(NodeForm.identifier(IdentifierAst { name }), span);
            self.state.node_symbols[value.id] = symbol;
            var label: String? = nil; if index < labels.len() { label = labels[index]; }
            params.push((pattern, untyped)); arguments.push(arena.add(NodeForm.argument(ArgumentAst { label, value }), span));
        }
        let callee = arena.add(NodeForm.member_access(MemberAccessAst { object: holder, member: data.member }), span);
        let call = arena.add(NodeForm.call(CallAst { callee, arguments, is_interpolation: false }), span);
        var body = arena.add(NodeForm.return_stmt(ReturnStmtAst { value: call, implicit: true }), span);
        if func.return_type == self.state.type_table.void_type { body = arena.add(NodeForm.expr_stmt(ExprStmtAst { expr: call }), span); }
        let lambda = arena.add(NodeForm.lambda(LambdaAst { params, body: [body], return_type: nil }), span);
        self.state.synthetic_lambda_types[lambda.id] = method.signature;
        let arm = arena.add(NodeForm.expr_stmt(ExprStmtAst { expr: lambda }), span);
        let branch = arena.add(NodeForm.switch_case(SwitchCaseAst { patterns: [(receiver_pattern, untyped)], body: [arm], is_default: false }), span);
        let value = arena.add(NodeForm.switch_expr(SwitchExprAst { value: data.object, cases: [branch] }), span);
        self.state.lowered_expressions[id.id] = value;
        self.infer_expr(value)
    }
    def is_variable(type: TypeId) -> Bool { if let info = self.state.type_table.get_type(type) { switch info.data { case .type_variable: return true; default: {} } } false }
    def is_heap(type: TypeId) -> Bool { if let info = self.state.type_table.get_type(type) { switch info.data { case .struct_type | .enum_type: return true; default: {} } } false }
    def cast(id: NodeId, data: CastAst) -> TypeId {
        let source = self.state.infer_with_expected(data.expr, nil);
        guard let target_node = data.target_type else { return self.state.type_table.error_type; }
        let target = self.state.resolve_type(target_node);
        if data.kind.equals("optional") || data.kind.equals("forced") { return self.downcast(id, source, target, data.kind.equals("forced")); }
        if self.state.is_raw_ptr(source) || self.state.is_raw_ptr(target) { self.state.require_unsafe("casting to or from RawPtr", id); return target; }
        if self.state.type_table.is_error(source) || self.state.type_table.is_error(target) || self.state.types_equal(source, target) || self.is_variable(source) || self.is_variable(target) { return target; }
        let table = self.state.type_table;
        if table.is_numeric(source) && table.is_numeric(target) || table.is_bool(source) && table.is_numeric(target) || table.is_numeric(source) && table.is_bool(target) { return target; }
        if let inner = table.get_optional_inner(target) { if self.state.types_equal(source, inner) || table.is_error(inner) { return target; } }
        var message = f"cannot cast {table.format_type(source)} to {table.format_type(target)} using `as`. ";
        if self.is_heap(source) {
            if self.is_heap(target) { message += "Heap types cannot be reinterpreted as other heap types; construct the target type explicitly."; }
            else if table.is_numeric(target) { message += "Heap types cannot be reinterpreted as integers."; }
            else { message += "Heap-to-non-heap casts are not allowed."; }
        } else if table.is_existential(source) { message += "Existential downcasts via `as` are not supported; use the runtime-checked operators `as?` (optional) or `as!` (force-unwrap) instead."; }
        else { message += "Only numeric, bool and identity casts are allowed in safe code."; }
        self.state.error(TypeErrorKind.invalid_operation(), message, id); target
    }
    def downcast(id: NodeId, source: TypeId, target: TypeId, forced: Bool) -> TypeId {
        var result = target; if !forced { result = self.state.type_table.make_optional(target); }
        if self.state.type_table.is_error(source) || self.state.type_table.is_error(target) || self.is_variable(source) || self.is_variable(target) { return result; }
        var protocol: TypeId? = nil;
        if let info = self.state.type_table.get_type(source) { switch info.data { case .existential(let data): protocol = data.protocol_id; default: {} } }
        guard let p = protocol else {
            var suffix = "?"; if forced { suffix = "!"; }
            self.state.error(TypeErrorKind.invalid_operation(), f"runtime downcast `as{suffix}` requires an existential source; got {self.state.type_table.format_type(source)}", id); return result;
        }
        if !self.is_heap(target) { self.state.error(TypeErrorKind.invalid_operation(), f"runtime downcast target must be a concrete struct or enum type, got {self.state.type_table.format_type(target)}", id); return result; }
        if !self.state.conformance_checker.check_conformance(target, p).conforms { self.state.error(TypeErrorKind.invalid_operation(), f"{self.state.type_table.format_type(target)} does not conform to {self.state.type_table.format_type(p)}; runtime downcast can never succeed", id); }
        result
    }
    def propagate(id: NodeId, type: TypeId, op: String) -> TypeId {
        if let inner = self.state.type_table.get_optional_inner(type) {
            var optional_return = false; if let ret = self.state.current_function_return { optional_return = self.state.type_table.is_optional(ret); }
            if !optional_return { self.state.error(TypeErrorKind.invalid_operation(), f"'{op}' on an optional requires an optional return type"); return self.state.type_table.error_type; }
            return inner;
        }
        let operand = result_payloads(type, self.state.type_table, self.state.symbol_table, self.state.arena, self.state.type_resolver);
        guard let payloads = operand else { self.state.error(TypeErrorKind.invalid_operation(), f"'{op}' requires a Result type with single-payload 'ok' and 'err' cases"); return self.state.type_table.error_type; }
        var target: Dict<String, TypeId>? = nil; if let ret = self.state.current_function_return { target = result_payloads(ret, self.state.type_table, self.state.symbol_table, self.state.arena, self.state.type_resolver); }
        guard let expected = target else { self.state.error(TypeErrorKind.invalid_operation(), f"'{op}' can only be used in a function that returns a Result type"); return self.state.type_table.error_type; }
        let actual = payloads["err"] ?? self.state.type_table.error_type; let want = expected["err"] ?? self.state.type_table.error_type;
        if !self.state.types_equal(actual, want) { self.state.error(TypeErrorKind.type_mismatch(), f"Cannot propagate error type '{self.state.type_table.format_type(actual)}' to '{self.state.type_table.format_type(want)}' via '{op}'"); }
        self.state.result.propagation_error_types[id.id] = actual; payloads["ok"] ?? self.state.type_table.error_type
    }
    def intrinsic(id: NodeId, arg: NodeId?, kind: String) -> TypeId {
        guard let ref = arg else { return self.state.type_table.error_type; }
        let type = self.state.resolve_type(ref); self.state.result.intrinsic_types[id.id] = type;
        if kind.equals("size") { self.state.result.intrinsic_values[id.id] = self.state.layout.size_of(type); }
        else if kind.equals("align") { self.state.result.intrinsic_values[id.id] = self.state.layout.align_of(type); }
        else if kind.equals("drop") || kind.equals("clone") {
            var name = "clone"; if kind.equals("drop") { name = "__release__"; }
            var present: i64 = 0; if let method = self.state.member_resolver.get_method(type, name) { present = 1; }
            self.state.result.intrinsic_values[id.id] = present; return self.state.builtin("Bool");
        }
        self.state.builtin("i32")
    }
    def optional_chain(id: NodeId, data: OptionalChainAst) -> TypeId {
        let type = self.state.infer_expr(data.object); let base = self.state.type_table.get_optional_inner(type) ?? type;
        var has_member = false; if let field = self.state.member_resolver.get_field(base, data.member) { has_member = true; }
        if let method = self.state.member_resolver.get_method(base, data.member) { has_member = true; }
        if let suffix = data.suffix { has_member = true; }
        if has_member {
            // Check `object?.field`, `object?.method`, `object?.member(args)` and `object?.member[indices]` as an ordinary
            // expression on a binding of the unwrapped object; HIR wraps it in the optional match.
            var span: Span? = nil; if let node = self.state.arena.get(id) { span = node.span; }
            let holder = self.state.arena.add(NodeForm.identifier(IdentifierAst { name: "__opt_chain" }), span);
            let binding = self.state.symbol_table.create_symbol("__opt_chain", SymbolKind.variable(), Namespace.value()).id;
            self.state.node_symbols[holder.id] = binding; self.state.type_env[binding.id] = base;
            let member = self.state.arena.add(NodeForm.member_access(MemberAccessAst { object: holder, member: data.member }), span);
            var content = member;
            if let suffix = data.suffix { switch suffix {
                case .call(let args): content = self.state.arena.add(NodeForm.call(CallAst { callee: member, arguments: args, is_interpolation: false }), span);
                case .index(let indices): content = self.state.arena.add(NodeForm.subscript(SubscriptAst { object: member, indices }), span);
            } }
            self.state.lowered_expressions[id.id] = content;
            let result = self.infer_expr(content);
            if self.state.type_table.is_error(result) { return result; }
            if result == self.state.type_table.void_type { self.state.error(TypeErrorKind.invalid_operation(), f"Optional chaining cannot call '{data.member}' because it returns Void; unwrap the value with if let", id); return self.state.type_table.error_type; }
            // An optional result is not wrapped again, so `a?.b?.c` chains through optional members.
            if let inner = self.state.type_table.get_optional_inner(result) { return result; }
            return self.state.type_table.make_optional(result);
        }
        self.state.error(TypeErrorKind.undefined_member(), f"Type {self.state.type_table.format_type(base)} has no member '{data.member}'", id); self.state.type_table.error_type
    }
}
