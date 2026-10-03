// HIR -> explicit CFG MIR. This pass consumes monomorphized HIR only.
pub import "monomorphize.rl"
pub import "mir.rl"
pub import "capture_analysis.rl"
import "operators.rl"
import "module_abi.rl"

struct MirLoopScope { let header: MirBlockId; let exit: MirBlockId; let defer_depth: i32; }
pub struct MirPendingLambda { pub let name: String; pub let lambda: HirLambdaData; pub let captures: Vec<CaptureInfo>; pub let closure_type: TypeId; pub let location: HirLocation?; }

pub struct MirFunctionBuilder {
    pub let ast: AstArena;
    pub let hir: HirArena;
    pub let program: HirId;
    pub let func: HirFunctionData;
    pub let types: TypeTable;
    pub let symbols: SymbolTable;
    pub let members: MemberResolver;
    pub let args: Vec<MirLocal>;
    pub let locals: Vec<MirLocal>;
    pub let blocks: Dict<i32, MirBlock>;
    pub let block_order: Vec<MirBlockId>;
    pub let errors: Vec<String>;
    pub let bindings: Dict<i32, MirLocalId>;
    pub let pending_lambdas: Vec<MirPendingLambda>;
    // Starters for named async functions used as values (see mir_async_starter).
    pub let pending_starters: Vec<MirFunction>;
    pub var captures: Vec<CaptureInfo>;
    pub var lambda_mode: Bool;
    // With -g, statements and the function entry are preceded by debug_location ops.
    pub var debug: Bool;
    pub var location: HirLocation?;
    var next_value_id: i32;
    var current: MirBlockId?;
    var loops: Vec<MirLoopScope>;
    var defer_scopes: Vec<Vec<HirId>>;
    pub static def new(ast: AstArena, hir: HirArena, program: HirId, func: HirFunctionData, types: TypeTable, symbols: SymbolTable) -> MirFunctionBuilder {
        MirFunctionBuilder { ast, hir, program, func, types, symbols, members: MemberResolver.new(ast, types, symbols), args: Vec<MirLocal>.new(), locals: Vec<MirLocal>.new(),
            blocks: Dict<i32, MirBlock>.with_capacity(16, 0), block_order: Vec<MirBlockId>.new(),
            errors: Vec<String>.new(), bindings: Dict<i32, MirLocalId>.with_capacity(16, 0),
            pending_lambdas: Vec<MirPendingLambda>.new(), pending_starters: Vec<MirFunction>.new(), captures: Vec<CaptureInfo>.new(), lambda_mode: false, debug: false, location: nil, next_value_id: 0,
            current: nil, loops: Vec<MirLoopScope>.new(), defer_scopes: Vec<Vec<HirId>>.new() }
    }
    def void_type() -> TypeId { self.types.void_type }
    def bool_type() -> TypeId { self.types.get_builtin("Bool") ?? self.types.error_type }
    def i32_type() -> TypeId { self.types.get_builtin("i32") ?? self.types.error_type }
    def hir_type(id: HirId) -> TypeId { self.hir.type_of(id, self.types.error_type) }
    pub def create_local(name: String, type_id: TypeId, is_mutable: Bool = false,
                         is_arg: Bool = false, symbol_id: SymbolId? = nil) -> MirLocalId {
        let id = MirLocalId { id: self.locals.len() };
        let local = MirLocal { id, symbol_id, name, type_id, is_mutable, is_arg };
        self.locals.push(local); if is_arg { self.args.push(local); }
        if let symbol = symbol_id { self.bindings[symbol.id] = id; }
        id
    }
    pub def temp(type_id: TypeId, prefix: String = "__tmp") -> MirLocalId {
        self.create_local(f"{prefix}_{self.locals.len()}", type_id)
    }
    pub def get_local(id: MirLocalId) -> MirLocal? {
        if id.id >= 0 && id.id < self.locals.len() { return self.locals[id.id]; } nil
    }
    pub def create_block() -> MirBlockId {
        let id = MirBlockId { id: self.block_order.len() };
        self.blocks[id.id] = MirBlock { id, ops: Vec<MirOp>.new(), terminator: nil };
        self.block_order.push(id); id
    }
    pub def switch_to(id: MirBlockId) -> Void { self.current = id; }
    pub def current_block() -> MirBlock? { if let id = self.current { return self.blocks[id.id]; } nil }
    pub def is_terminated() -> Bool { if let block = self.current_block() { return block.is_terminated(); } false }
    pub def emit(op: MirOp) -> Void {
        if let block = self.current_block() { if !block.is_terminated() { block.ops.push(op); } }
    }
    pub def terminate(term: MirTerm) -> Void {
        if let block = self.current_block() { if !block.is_terminated() { block.terminator = term; } }
    }
    def branch(target: MirBlockId) -> Void { self.terminate(MirTerm.branch(MirBranchData { target })); }
    def cond_branch(value: MirOperand, yes: MirBlockId, no: MirBlockId) -> Void {
        self.terminate(MirTerm.cond_branch(MirCondBranchData { condition: value, true_target: yes, false_target: no }));
    }
    def return_term(value: MirOperand? = nil) -> Void { self.terminate(MirTerm.return_stmt(MirReturnData { value })); }
    def place(id: MirLocalId, type_id: TypeId) -> MirPlace { MirPlace { base: id, projections: Vec<MirProjection>.new(), type_id } }
    def copy(id: MirLocalId, type_id: TypeId) -> MirOperand { mir_copy(id, type_id) }
    def nil_operand(type_id: TypeId) -> MirOperand { mir_constant(MirConstantKind.nil(), MirScalar.none(), type_id) }
    def int_operand(value: String, type_id: TypeId) -> MirOperand { mir_constant(MirConstantKind.int(), MirScalar.integer(value), type_id) }
    def bool_operand(value: Bool) -> MirOperand { mir_constant(MirConstantKind.bool_type(), MirScalar.boolean(value), self.bool_type()) }
    def assign(place: MirPlace, value: MirOperand) -> Void { self.emit(MirOp.assign(MirAssignData { place, value })); }
    pub def build() -> MirFunction {
        let entry = self.create_block(); self.switch_to(entry);
        self.mark(self.location);
        var param_index = 0;
        for param in self.func.params { if let node = self.hir.get(param) { switch node.form { case .param(let data):
            var symbol_id: SymbolId? = data.symbol_id;
            if self.func.is_method && data.name.equals("self") && data.symbol_id.id == -1 { symbol_id = nil; }
            let local = self.create_local(data.name, data.type_id, false, true, symbol_id);
            if self.lambda_mode && param_index == 0 { var capture_index = 0; for capture in self.captures {
                let capture_local = self.create_local(capture.name, capture.type_id, false, false, capture.symbol_id);
                self.emit(MirOp.extract_closure_capture(MirExtractClosureCaptureData { result: capture_local,
                    closure: self.copy(local, data.type_id), capture_index, result_type: capture.type_id })); capture_index += 1;
            } }
            default: {}
        } } param_index += 1; }
        self.defer_scopes.push(Vec<HirId>.new());
        if let body = self.func.body { self.lower_block(body); }
        self.defer_scopes.pop();
        if !self.is_terminated() {
            if self.func.return_type == self.void_type() { self.return_term(); }
            else { self.terminate(MirTerm.unreachable()); }
        }
        var symbol_id: SymbolId? = self.func.symbol_id; if self.lambda_mode { symbol_id = nil; }
        var name = self.func.name;
        if self.func.is_async { name = abi_async_name(self.func.symbol_id, name, self.symbols, self.types); }
        MirFunction { name, symbol_id, args: self.args, locals: self.locals,
            ret_type: self.func.return_type, blocks: self.blocks, block_order: self.block_order, entry_block: entry,
            is_async: self.func.is_async, is_method: self.func.is_method }
    }
    def register_defer(body: HirId) -> Void {
        if self.defer_scopes.len() > 0 { self.defer_scopes[self.defer_scopes.len() - 1].push(body); }
    }
    def emit_defers(up_to: i32 = 0) -> Void {
        var depth = self.defer_scopes.len() - 1;
        while depth >= up_to {
            let scope = self.defer_scopes[depth]; var index = scope.len() - 1;
            while index >= 0 { self.lower_block(scope[index]); index -= 1; }
            depth -= 1;
        }
    }
    pub def lower_block(id: HirId) -> Void {
        guard let node = self.hir.get(id) else { return; }
        switch node.form { case .block(let data):
            self.defer_scopes.push(Vec<HirId>.new());
            for statement in data.statements { if self.is_terminated() { break; } self.lower_stmt(statement); }
            let scope = self.defer_scopes.pop();
            if !self.is_terminated() { var index = scope.len() - 1; while index >= 0 { self.lower_block(scope[index]); index -= 1; } }
            default: self.errors.push(internal_compiler_error("Expected HIR block"));
        }
    }
    def mark(location: HirLocation?) -> Void {
        if !self.debug { return; }
        if let at = location { self.emit(MirOp.debug_location(MirDebugLocationData { file: at.file, line: at.line, column: at.column })); }
    }
    pub def lower_stmt(id: HirId) -> Void {
        guard let node = self.hir.get(id) else { return; }
        self.mark(self.hir.location(id));
        switch node.form {
            case .block: self.lower_block(id);
            case .var_decl(let data): self.lower_var_decl(data);
            case .assign(let data): self.lower_assign(data);
            case .expr_stmt(let data): self.lower_expr(data.expr);
            case .return_stmt(let data): self.lower_return(data);
            case .break_stmt: self.lower_break();
            case .continue_stmt: self.lower_continue();
            case .if_stmt(let data): self.lower_if(data);
            case .if_let(let data): self.lower_if_let(data);
            case .guard_stmt(let data): self.lower_guard(data);
            case .while_stmt(let data): self.lower_while(data);
            case .for_stmt(let data): self.lower_for(data);
            case .switch_stmt(let data): self.lower_switch(data);
            case .defer_stmt(let data): self.register_defer(data.body);
            default: self.errors.push(internal_compiler_error("MIR statement lowering pending: " + node.form.kind()));
        }
    }
    def default_init(local: MirLocalId, type_id: TypeId) -> Void {
        let place = self.place(local, type_id);
        if self.types.is_heap_type(type_id) {
            let allocated = self.temp(type_id);
            self.emit(MirOp.alloc_obj(MirAllocObjData { result: allocated, type_id: 0, payload_size: 0, result_type: type_id }));
            self.assign(place, self.copy(allocated, type_id)); return;
        }
        if let info = self.types.get_type(type_id) { switch info.data {
            case .optional: let none = self.temp(type_id); self.emit(MirOp.make_none(MirMakeNoneData { result: none, result_type: type_id })); self.assign(place, self.copy(none, type_id));
            case .primitive(let primitive): switch primitive {
                case .bool_type: self.assign(place, self.bool_operand(false));
                case .f32 | .f64: self.assign(place, mir_constant(MirConstantKind.float(), MirScalar.floating(0.0), type_id));
                case .raw_ptr: self.assign(place, self.nil_operand(type_id));
                case .void_type: {}
                default: self.assign(place, self.int_operand("0", type_id));
            }
            default: {}
        } }
    }
    def lower_var_decl(data: HirVarDeclData) -> Void {
        let local = self.create_local(data.name, data.type_id, data.is_mutable, false, data.symbol_id);
        if let initial = data.initializer {
            let operand = self.coerce(self.lower_expr(initial), data.type_id);
            if self.types.is_closure(operand.type_id()) {
                self.locals[local.id] = MirLocal { id: local, symbol_id: data.symbol_id, name: data.name,
                    type_id: operand.type_id(), is_mutable: data.is_mutable, is_arg: false };
            }
            self.assign(self.place(local, self.locals[local.id].type_id), operand);
        } else { self.default_init(local, data.type_id); }
    }
    pub def coerce(value: MirOperand, target: TypeId) -> MirOperand {
        let source = value.type_id(); if source == target { return value; }
        if let info = self.types.get_type(target) { switch info.data { case .existential(let data):
            let local = self.temp(target);
            self.emit(MirOp.box_existential(MirBoxExistentialData { result: local, value,
                concrete_type: source, protocol_type: data.protocol_id, result_type: target }));
            return self.copy(local, target);
            default: {}
        } }
        if let inner = self.types.get_optional_inner(target) {
            switch value { case .constant(let constant): switch constant.kind { case .nil: let local = self.temp(target);
                self.emit(MirOp.make_none(MirMakeNoneData { result: local, result_type: target })); return self.copy(local, target);
                default: {}
            } default: {} }
            let content = self.coerce(value, inner);
            if content.type_id() == inner { let local = self.temp(target);
                self.emit(MirOp.make_some(MirMakeSomeData { result: local, value: content, result_type: target })); return self.copy(local, target);
            }
        }
        if self.types.can_widen_int(source, target) { let local = self.temp(target);
            self.emit(MirOp.cast_op(MirCastOpData { result: local, operand: value, target_type: target })); return self.copy(local, target);
        }
        value
    }
    def lower_return(data: HirReturnData) -> Void {
        var result: MirOperand? = nil;
        if let value = data.value {
            let lowered = self.lower_expr(value);
            if self.func.return_type != self.void_type() { result = self.coerce(lowered, self.func.return_type); }
        }
        if let operand = result { if self.defer_scopes.len() > 0 {
            var deferred = false; for scope in self.defer_scopes { if scope.len() > 0 { deferred = true; } }
            if deferred { let saved = self.temp(self.func.return_type); self.assign(self.place(saved, self.func.return_type), operand);
                result = self.copy(saved, self.func.return_type);
            }
        } }
        self.emit_defers(); self.return_term(result);
    }
    def lower_break() -> Void {
        if self.loops.len() == 0 { self.errors.push("break outside of loop"); return; }
        let loop = self.loops[self.loops.len()-1]; self.emit_defers(loop.defer_depth); self.branch(loop.exit);
    }
    def lower_continue() -> Void {
        if self.loops.len() == 0 { self.errors.push("continue outside of loop"); return; }
        let loop = self.loops[self.loops.len()-1]; self.emit_defers(loop.defer_depth); self.branch(loop.header);
    }
    def lower_if(data: HirIfData) -> Void {
        let condition = self.lower_expr(data.condition); let yes = self.create_block(); let merge = self.create_block();
        if let other = data.else_block {
            let no = self.create_block(); self.cond_branch(condition, yes, no);
            self.switch_to(yes); self.lower_block(data.then_block); if !self.is_terminated() { self.branch(merge); }
            self.switch_to(no); self.lower_else(other);
            if !self.is_terminated() { self.branch(merge); }
        } else {
            self.cond_branch(condition, yes, merge);
            self.switch_to(yes); self.lower_block(data.then_block); if !self.is_terminated() { self.branch(merge); }
        }
        self.switch_to(merge);
    }
    def lower_guard(data: HirGuardData) -> Void {
        let condition = self.lower_expr(data.condition); let next = self.create_block(); let failed = self.create_block();
        self.cond_branch(condition, next, failed); self.switch_to(failed); self.lower_block(data.else_block);
        if !self.is_terminated() { self.terminate(MirTerm.unreachable()); }
        self.switch_to(next);
    }
    def lower_while(data: HirWhileData) -> Void {
        let header = self.create_block(); let body = self.create_block(); let done = self.create_block(); self.branch(header);
        self.switch_to(header); let condition = self.lower_expr(data.condition); self.cond_branch(condition, body, done);
        self.switch_to(body); self.loops.push(MirLoopScope { header, exit: done, defer_depth: self.defer_scopes.len() });
        self.lower_block(data.body); self.loops.pop(); if !self.is_terminated() { self.branch(header); }
        self.switch_to(done);
    }
    def lower_assign(data: HirAssignData) -> Void {
        if self.try_subscript_set(data) { return; }
        let value = self.lower_expr(data.value);
        guard let target = self.lower_place(data.target) else { return; }
        var result = self.coerce(value, target.type_id);
        if let op = data.compound_op {
            if op.equals("+") && self.types.is_string(target.type_id) {
                let local = self.temp(target.type_id); let args = Vec<MirOperand>.new();
                args.push(MirOperand.copy(target)); args.push(result);
                self.emit(MirOp.call_static(MirCallStaticData { result: local,
                    func_name: self.type_prefix(target.type_id) + "___add__", func_symbol: nil,
                    args, result_type: target.type_id }));
                result = self.copy(local, target.type_id);
            } else if let binary = binary_op(op) {
                let local = self.temp(target.type_id);
                self.emit(MirOp.bin_op(MirBinOpData { result: local, op: binary, left: MirOperand.copy(target),
                    right: result, result_type: target.type_id }));
                result = self.copy(local, target.type_id);
            } else { self.errors.push(internal_compiler_error("Unknown compound assignment operator: " + op)); }
        }
        self.assign(target, result);
    }
    def lower_place(id: HirId) -> MirPlace? {
        guard let node = self.hir.get(id) else { return nil; }
        switch node.form {
            case .var_ref(let data):
                if let local = self.bindings[data.symbol_id.id] { return self.place(local, self.locals[local.id].type_id); }
                self.errors.push(internal_compiler_error("Undefined assignment target: " + data.name));
            case .field_access(let data):
                if let base = self.lower_place(data.object) {
                    let projections = Vec<MirProjection>.new(); for p in base.projections { projections.push(p); }
                    var name = data.field_name;
                    if let info = self.types.get_type(base.type_id) { switch info.data { case .struct_type(let type_data):
                        if let fields = type_data.anon_fields { for field in fields.to_vec() { if field.name.equals(name) { name = field.name; } } }
                        default: {}
                    } }
                    projections.push(MirProjection.field(name, data.type_id));
                    return MirPlace { base: base.base, projections, type_id: data.type_id };
                }
            case .subscript(let data): if let base = self.lower_place(data.object) {
                if data.indices.len() == 0 { return base; }
                let projections = Vec<MirProjection>.new(); for projection in base.projections { projections.push(projection); }
                if let literal = self.hir.get(data.indices[0]) { switch literal.form { case .literal(let value): switch value.value {
                    case .integer(let index): if let field = self.tuple_field(base.type_id, index.to_i32()) {
                        projections.push(MirProjection.field(field.name, data.type_id)); return MirPlace { base: base.base, projections, type_id: data.type_id };
                    } default: {}
                } default: {} } }
                projections.push(MirProjection.index(self.lower_expr(data.indices[0]), data.type_id));
                return MirPlace { base: base.base, projections, type_id: data.type_id };
            }
            default: let value = self.lower_expr(id); let local = self.temp(value.type_id()); let place = self.place(local, value.type_id()); self.assign(place, value); return place;
        }
        nil
    }
    def lower_literal(data: HirLiteralData) -> MirOperand {
        var operand = self.nil_operand(data.type_id);
        switch data.value {
            case .integer(let value): operand = self.int_operand(value, data.type_id);
            case .floating(let value): operand = mir_constant(MirConstantKind.float(), MirScalar.floating(value), data.type_id);
            case .boolean(let value): operand = mir_constant(MirConstantKind.bool_type(), MirScalar.boolean(value), data.type_id);
            case .text(let value): operand = mir_constant(MirConstantKind.string(), MirScalar.text(value), data.type_id);
            case .type_id(let type_id): operand = self.int_operand(f"{self.types.runtime_type_id(type_id)}", data.type_id);
            case .none: {}
        }
        if data.kind.equals("string") {
            let local = self.temp(data.type_id, "__strlit"); self.assign(self.place(local, data.type_id), operand);
            return self.copy(local, data.type_id);
        }
        operand
    }
    def lower_binary(data: HirBinaryOpData) -> MirOperand {
        if is_short_circuit_op(data.op) {
            let result = self.temp(self.bool_type()); let result_place = self.place(result, self.bool_type());
            let left = self.lower_expr(data.left);
            let and_op = is_short_circuit_and_op(data.op);
            let first = self.create_block(); let second = self.create_block(); let merge = self.create_block();
            var right_block = first; var short_block = second; if !and_op { right_block = second; short_block = first; }
            if and_op { self.cond_branch(left, right_block, short_block); }
            else { self.cond_branch(left, short_block, right_block); }
            self.switch_to(short_block); self.assign(result_place, self.bool_operand(!and_op)); self.branch(merge);
            self.switch_to(right_block); let right = self.lower_expr(data.right); self.assign(result_place, right); self.branch(merge);
            self.switch_to(merge); return self.copy(result, self.bool_type());
        }
        let left = self.lower_expr(data.left); let right = self.lower_expr(data.right);
        let result = self.temp(data.type_id);
        if let op = binary_op(data.op) {
            self.emit(MirOp.bin_op(MirBinOpData { result, op, left, right, result_type: data.type_id }));
        } else if let op = comparison_op(data.op) {
            self.emit(MirOp.cmp_op(MirCmpOpData { result, op, left, right }));
        } else { self.errors.push(internal_compiler_error("Unknown binary operator: " + data.op)); }
        self.copy(result, data.type_id)
    }
    def lower_ternary(data: HirTernaryData) -> MirOperand {
        let condition = self.lower_expr(data.condition);
        let local = self.temp(data.type_id); let result = self.place(local, data.type_id);
        let yes = self.create_block(); let no = self.create_block(); let merge = self.create_block();
        self.cond_branch(condition, yes, no);
        self.switch_to(yes); let yes_value = self.coerce(self.lower_expr(data.then_expr), data.type_id); self.assign(result, yes_value); self.branch(merge);
        self.switch_to(no); let no_value = self.coerce(self.lower_expr(data.else_expr), data.type_id); self.assign(result, no_value); self.branch(merge);
        self.switch_to(merge); self.copy(local, data.type_id)
    }
    def lower_call(data: HirCallData) -> MirOperand {
        let args = Vec<MirOperand>.new(); for arg in data.arguments { args.push(self.lower_expr(arg.1)); }
        let callee_type = self.hir_type(data.callee);
        var is_async = false;
        if let signature = self.types.get_function_data(callee_type) {
            is_async = signature.is_async;
            var index = 0; while index < args.len() && index < signature.params.len() {
                args[index] = self.coerce(args[index], signature.params.get(index)); index += 1;
            }
        } else if let signature = self.types.get_closure_data(callee_type) {
            is_async = signature.is_async;
            var index = 0; while index < args.len() && index < signature.params.len() {
                args[index] = self.coerce(args[index], signature.params.get(index)); index += 1;
            }
        }
        var name = "<unknown>"; var local_callee: MirOperand? = nil;
        if let node = self.hir.get(data.callee) { switch node.form {
            case .var_ref(let variable):
                name = variable.name;
                if let id = self.bindings[variable.symbol_id.id] { local_callee = self.copy(id, self.locals[id.id].type_id); }
            default: local_callee = self.lower_expr(data.callee);
        } }
        var result: MirLocalId? = nil;
        if data.type_id != self.void_type() { result = self.temp(data.type_id); }
        if let callee = local_callee {
            if is_async {
                // The closure's starter returns the spawned task; the call awaits and then releases it.
                let ptr_type = self.types.get_builtin("RawPtr") ?? self.void_type(); let handle = self.temp(ptr_type);
                self.emit(MirOp.call_closure(MirCallClosureData { result: handle, closure: callee, args, result_type: ptr_type }));
                self.static_call(result, "__rolang_await_started_task", [self.copy(handle, ptr_type)], data.type_id);
                if let local = result { return self.copy(local, data.type_id); }
                return mir_unit(self.void_type());
            }
            self.emit(MirOp.call_closure(MirCallClosureData { result, closure: callee, args, result_type: data.type_id }));
        } else {
            if is_async { if let symbol = data.callee_symbol { name = abi_async_name(symbol, name, self.symbols, self.types); } }
            self.emit(MirOp.call_static(MirCallStaticData { result, func_name: name, func_symbol: data.callee_symbol,
                args, result_type: data.type_id }));
        }
        if let local = result { return self.copy(local, data.type_id); }
        mir_unit(self.void_type())
    }
    def type_prefix(type_id: TypeId) -> String {
        if let info = self.types.get_type(type_id) { switch info.data {
            case .struct_type(let data): if let id = data.symbol_id {
                if let symbol = self.symbols.get_symbol(id) {
                    if data.type_args.len() == 0 { return symbol.name; }
                    return mangle_name(symbol.name, data.type_args, self.types);
                }
            }
            case .enum_type(let data): if let symbol = self.symbols.get_symbol(data.symbol_id) { return symbol.name; }
            case .primitive(let primitive): return primitive.spelling();
            default: {}
        } }
        "<error>"
    }
    def lower_method_call(data: HirMethodCallData) -> MirOperand {
        let receiver_type = self.hir_type(data.receiver);
        var receiver: MirOperand? = nil;
        if !data.is_static { receiver = self.lower_expr(data.receiver); }
        let args = Vec<MirOperand>.new();
        for arg in data.arguments { args.push(self.lower_expr(arg.1)); }
        var is_async = false;
        if let method = self.members.get_method(receiver_type, data.method_name, data.is_static) {
            if let signature = self.types.get_function_data(method.signature) {
                is_async = signature.is_async;
                var index = 0; while index < args.len() && index < signature.params.len() {
                    args[index] = self.coerce(args[index], signature.params.get(index)); index += 1;
                }
            }
        }
        var result: MirLocalId? = nil;
        if data.type_id != self.void_type() { result = self.temp(data.type_id); }
        if let info = self.types.get_type(receiver_type) { switch info.data {
            case .existential:
                if let value = receiver {
                    self.emit(MirOp.call_v_table(MirCallVTableData { result, receiver: value,
                        method_name: data.method_name, args, result_type: data.type_id }));
                    if let local = result { return self.copy(local, data.type_id); }
                    return mir_unit(self.void_type());
                }
            default: {}
        } }
        let full_args = Vec<MirOperand>.new(); if let value = receiver { full_args.push(value); }
        for arg in args { full_args.push(arg); }
        var name = self.type_prefix(receiver_type) + "_" + data.method_name;
        if is_async { if let symbol = data.method_symbol { name = abi_async_method_name(symbol, receiver_type, name, self.symbols, self.types); } }
        self.emit(MirOp.call_static(MirCallStaticData { result,
            func_name: name,
            func_symbol: data.method_symbol, args: full_args, result_type: data.type_id }));
        if let local = result { return self.copy(local, data.type_id); }
        mir_unit(self.void_type())
    }
    def lower_field_access(data: HirFieldAccessData) -> MirOperand {
        let object = self.lower_expr(data.object); let result = self.temp(data.type_id);
        var field_index = 0;
        if let field = self.members.get_field(object.type_id(), data.field_name) { field_index = field.index; }
        self.emit(MirOp.extract_field(MirExtractFieldData { result, aggregate: object,
            field_name: data.field_name, field_index, result_type: data.type_id }));
        self.copy(result, data.type_id)
    }
    def lower_tuple(data: HirTupleData) -> MirOperand {
        let fields = Vec<(String, MirOperand)>.new(); var index = 0;
        var names: FrozenVec<TupleField>? = nil;
        if let info = self.types.get_type(data.type_id) { switch info.data {
            case .struct_type(let struct_data): names = struct_data.anon_fields;
            default: {}
        } }
        for element in data.elements {
            var name = index.to_string(); var value = self.lower_expr(element.1);
            if let fields_meta = names { if index < fields_meta.len() { name = fields_meta.get(index).name; value = self.coerce(value, fields_meta.get(index).type_id); } }
            fields.push((name, value)); index += 1;
        }
        let result = self.temp(data.type_id);
        self.emit(MirOp.make_struct(MirMakeStructData { result, struct_type: data.type_id, fields }));
        self.copy(result, data.type_id)
    }
    def lower_struct_init(data: HirStructInitData) -> MirOperand {
        let fields = Vec<(String, MirOperand)>.new(); var index = 0;
        for argument in data.arguments {
            let name = argument.0 ?? f"_{index}";
            var value = self.lower_expr(argument.1);
            if let field = self.members.get_field(data.type_id, name) { value = self.coerce(value, field.type_id); }
            fields.push((name, value)); index += 1;
        }
        let result = self.temp(data.type_id);
        self.emit(MirOp.make_struct(MirMakeStructData { result, struct_type: data.struct_type, fields }));
        self.copy(result, data.type_id)
    }
    def lower_array(data: HirArrayData) -> MirOperand {
        let elements = Vec<MirOperand>.new(); for id in data.elements { elements.push(self.coerce(self.lower_expr(id), data.element_type)); }
        let result = self.temp(data.type_id); let prefix = self.type_prefix(data.type_id);
        let args = Vec<MirOperand>.new(); args.push(self.int_operand(f"{elements.len()}", self.i32_type()));
        self.emit(MirOp.call_static(MirCallStaticData { result, func_name: prefix + "_with_capacity",
            func_symbol: nil, args, result_type: data.type_id }));
        for element in elements {
            let args = Vec<MirOperand>.new(); args.push(self.copy(result, data.type_id)); args.push(element);
            self.emit(MirOp.call_static(MirCallStaticData { result: nil, func_name: prefix + "_push",
                func_symbol: nil, args, result_type: self.void_type() }));
        }
        self.copy(result, data.type_id)
    }
    def lower_dict(data: HirDictData) -> MirOperand {
        let entries = Vec<(MirOperand, MirOperand)>.new();
        for pair in data.entries { entries.push((self.coerce(self.lower_expr(pair.0), data.key_type), self.coerce(self.lower_expr(pair.1), data.value_type))); }
        let result = self.temp(data.type_id); let prefix = self.type_prefix(data.type_id);
        let args = Vec<MirOperand>.new(); args.push(self.int_operand(f"{entries.len()}", self.i32_type()));
        if self.types.is_string(data.key_type) { args.push(self.int_operand("1", self.i32_type())); }
        else { args.push(self.int_operand("0", self.i32_type())); }
        self.emit(MirOp.call_static(MirCallStaticData { result, func_name: prefix + "_with_capacity",
            func_symbol: nil, args, result_type: data.type_id }));
        for pair in entries {
            let args = Vec<MirOperand>.new(); args.push(self.copy(result, data.type_id));
            args.push(pair.0); args.push(pair.1);
            self.emit(MirOp.call_static(MirCallStaticData { result: nil, func_name: prefix + "_set",
                func_symbol: nil, args, result_type: self.void_type() }));
        }
        self.copy(result, data.type_id)
    }
    def lower_subscript(data: HirSubscriptData) -> MirOperand {
        let object = self.lower_expr(data.object);
        if data.indices.len() == 0 { return object; }
        if let info = self.types.get_type(object.type_id()) { switch info.data {
            case .struct_type(let struct_data):
                if let fields = struct_data.anon_fields {
                    if let index_node = self.hir.get(data.indices[0]) { switch index_node.form {
                        case .literal(let literal): switch literal.value {
                            case .integer(let value): let index = value.to_i32();
                                if index >= 0 && index < fields.len() {
                                    let result = self.temp(data.type_id);
                                    self.emit(MirOp.extract_field(MirExtractFieldData { result, aggregate: object,
                                        field_name: fields.get(index).name, field_index: index, result_type: data.type_id }));
                                    return self.copy(result, data.type_id);
                                }
                            default: {}
                        }
                        default: {}
                    } }
                }
            default: {}
        } }
        let indices = Vec<MirOperand>.new(); for id in data.indices { indices.push(self.lower_expr(id)); }
        let result = self.temp(data.type_id);
        let prefix = self.type_prefix(object.type_id());
        var function = ""; var symbol: SymbolId? = nil;
        if prefix.equals("Vec") || prefix.starts_with("Vec_") || prefix.equals("Dict") || prefix.starts_with("Dict_") {
            function = prefix + "_get";
        } else if let method = self.members.get_method(object.type_id(), "__get__") {
            function = prefix + "___get__"; symbol = method.symbol_id;
            if let signature = self.types.get_function_data(method.signature) { for i in 0..<indices.len() { if i < signature.params.len() { indices[i] = self.coerce(indices[i], signature.params.get(i)); } } }
        }
        if function.len() == 0 { self.errors.push("Cannot subscript type " + self.types.format_type(object.type_id())); }
        else {
            let args = Vec<MirOperand>.new(); args.push(object); for index in indices { args.push(index); }
            self.emit(MirOp.call_static(MirCallStaticData { result, func_name: function, func_symbol: symbol,
                args, result_type: data.type_id }));
        }
        self.copy(result, data.type_id)
    }
    def enum_tag(enum_type: TypeId, case_name: String) -> i32 {
        if self.types.is_optional(enum_type) { if case_name.equals("Some") { return 1; } return 0; }
        guard let info = self.types.get_type(enum_type) else { return 0; }
        var symbol_id = SymbolId { id: -1 };
        switch info.data { case .enum_type(let data): symbol_id = data.symbol_id; default: return 0; }
        guard let root = self.hir.get(self.program) else { return 0; }
        switch root.form { case .program(let program):
            for item_id in program.items { if let item = self.hir.get(item_id) { switch item.form {
                case .enum_type(let enum_def): if enum_def.symbol_id == symbol_id {
                    var tag = 0; for case_id in enum_def.cases { if let case_node = self.hir.get(case_id) { switch case_node.form {
                        case .enum_case(let value): if value.name.equals(case_name) { return tag; }
                        default: {}
                    } } tag += 1; }
                }
                default: {}
            } } }
            default: {}
        }
        0
    }
    def lower_enum_construct(data: HirEnumConstructData) -> MirOperand {
        let payload = Vec<MirOperand>.new(); var index = 0;
        for item in data.payload { var value = self.lower_expr(item.1);
            if let def = self.enum_case(data.enum_type, data.case_name) { if index < def.payload.len() { value = self.coerce(value, def.payload[index].1); } }
            payload.push(value); index += 1;
        }
        let result = self.temp(data.type_id);
        self.emit(MirOp.make_enum(MirMakeEnumData { result, enum_type: data.enum_type, case_name: data.case_name,
            tag: self.enum_tag(data.enum_type, data.case_name), payload }));
        self.copy(result, data.type_id)
    }
    def i64_type() -> TypeId { self.types.get_builtin("i64") ?? self.types.error_type }
    def compound_value(op: String, left: MirOperand, right: MirOperand, type_id: TypeId) -> MirOperand {
        let result = self.temp(type_id);
        if op.equals("+") && self.types.is_string(type_id) { self.static_call(result, self.type_prefix(type_id) + "___add__", [left, right], type_id); }
        else if let binary = binary_op(op) { self.emit(MirOp.bin_op(MirBinOpData { result, op: binary, left, right, result_type: type_id })); }
        self.copy(result, type_id)
    }
    def try_subscript_set(data: HirAssignData) -> Bool {
        guard let node = self.hir.get(data.target) else { return false; }
        switch node.form { case .subscript(let target):
            if target.indices.len() == 0 { return false; }
            let type_id = self.hir_type(target.object); var named = false;
            if let info = self.types.get_type(type_id) { switch info.data { case .struct_type(let struct_data): if let sid = struct_data.symbol_id { named = true; } default: {} } }
            if !named { return false; }
            let prefix = self.type_prefix(type_id); var name = ""; var get_name = ""; var symbol: SymbolId? = nil;
            if prefix.equals("Vec") || prefix.starts_with("Vec_") { name = prefix + "_set"; get_name = prefix + "_get"; }
            else if prefix.equals("Dict") || prefix.starts_with("Dict_") { name = prefix + "_set"; }
            else if let method = self.members.get_method(type_id, "__set__") { name = prefix + "___set__"; symbol = method.symbol_id;
                if let getter = self.members.get_method(type_id, "__get__") { get_name = prefix + "___get__"; }
            }
            if name.len() == 0 { return false; }
            let object = self.lower_expr(target.object); let indices = Vec<MirOperand>.new(); for id in target.indices { indices.push(self.lower_expr(id)); }
            var value = self.lower_expr(data.value);
            if let op = data.compound_op { if get_name.len() > 0 && is_arithmetic_op(op) || get_name.len() > 0 && is_bitwise_op(op) {
                let current = self.temp(target.type_id); let get_args = Vec<MirOperand>.new(); get_args.push(object); for index in indices { get_args.push(index); }
                self.static_call(current, get_name, get_args, target.type_id);
                value = self.compound_value(op, self.copy(current, target.type_id), value, target.type_id);
            } else { self.errors.push(f"compound assignment '{op}' to a '{prefix}' subscript is not supported"); return true; } }
            var method_name = "__set__"; if prefix.equals("Vec") || prefix.starts_with("Vec_") || prefix.equals("Dict") || prefix.starts_with("Dict_") { method_name = "set"; }
            if let setter = self.members.get_method(type_id, method_name) { if let signature = self.types.get_function_data(setter.signature) { if signature.params.len() == indices.len() + 1 {
                for i in 0..<indices.len() { indices[i] = self.coerce(indices[i], signature.params.get(i)); }
                value = self.coerce(value, signature.params.get(indices.len()));
            } } }
            let args = Vec<MirOperand>.new(); args.push(object); for index in indices { args.push(index); } args.push(value);
            self.static_call(nil, name, args, self.void_type(), symbol); return true;
            default: return false;
        }
    }
    def tuple_field(type_id: TypeId, index: i32) -> TupleField? {
        if let info = self.types.get_type(type_id) { switch info.data { case .struct_type(let data):
            if let fields = data.anon_fields { if index >= 0 && index < fields.len() { return fields.get(index); } }
            default: {}
        } } nil
    }
    def enum_case(enum_type: TypeId, name: String) -> HirEnumCaseData? {
        guard let info = self.types.get_type(enum_type) else { return nil; }
        var sid = SymbolId { id: -1 };
        switch info.data { case .enum_type(let data): sid = data.symbol_id; default: return nil; }
        guard let root = self.hir.get(self.program) else { return nil; }
        switch root.form { case .program(let data): for id in data.items { if let node = self.hir.get(id) { switch node.form {
            case .enum_type(let value): if value.symbol_id == sid { for case_id in value.cases {
                if let case_node = self.hir.get(case_id) { switch case_node.form {
                    case .enum_case(let case_data): if case_data.name.equals(name) { return case_data; }
                    default: {}
                } }
            } }
            default: {}
        } } } default: {} } nil
    }
    def pattern_type(id: HirId, owner: TypeId, case_name: String, index: i32) -> TypeId? {
        if let node = self.hir.get(id) {
            switch node.form { case .enum_case_pattern(let data): return data.enum_type; default: {} }
            if let type_id = node.form.type_id() { if !self.types.is_error(type_id) { return type_id; } }
        }
        if let inner = self.types.get_optional_inner(owner) { return inner; }
        if let data = self.enum_case(owner, case_name) { if index < data.payload.len() { return data.payload[index].1; } }
        nil
    }
    def extract_payload(value: MirOperand, name: String, index: i32, type_id: TypeId) -> MirOperand {
        let result = self.temp(type_id);
        self.emit(MirOp.extract_enum_payload(MirExtractEnumPayloadData { result, enum_val: value,
            case_name: name, payload_index: index, result_type: type_id })); self.copy(result, type_id)
    }
    def pattern_boolean(left: MirOperand, right: MirOperand, and_op: Bool) -> MirOperand {
        let result = self.temp(self.bool_type()); var op = BinOpKind.bit_or(); if and_op { op = BinOpKind.bit_and(); }
        self.emit(MirOp.bin_op(MirBinOpData { result, op, left, right, result_type: self.bool_type() }));
        self.copy(result, self.bool_type())
    }
    pub def bind_pattern(id: HirId, value: MirOperand) -> Void {
        guard let node = self.hir.get(id) else { return; }
        switch node.form {
            case .binding_pattern(let data): let local = self.create_local(data.name, data.type_id, data.is_mutable, false, data.symbol_id);
                self.assign(self.place(local, data.type_id), value);
            case .tuple_pattern(let data): var index = 0; for element in data.elements {
                if let field = self.tuple_field(data.type_id, index) { let local = self.temp(field.type_id);
                    self.emit(MirOp.extract_field(MirExtractFieldData { result: local, aggregate: value, field_name: field.name,
                        field_index: index, result_type: field.type_id })); self.bind_pattern(element.1, self.copy(local, field.type_id));
                } index += 1;
            }
            case .enum_case_pattern(let data): var index = 0; for pattern in data.payload {
                var wildcard = false; if let sub = self.hir.get(pattern) { switch sub.form { case .wildcard_pattern: wildcard = true; default: {} } }
                if !wildcard { if let type_id = self.pattern_type(pattern, data.enum_type, data.case_name, index) {
                    let payload = self.extract_payload(value, data.case_name, index, type_id); self.bind_pattern(pattern, payload);
                } } index += 1;
            }
            case .or_pattern(let data): if data.patterns.len() > 0 { self.bind_pattern(data.patterns[0], value); }
            default: {}
        }
    }
    def pattern_match(value: MirOperand, id: HirId) -> MirOperand? {
        guard let node = self.hir.get(id) else { return self.bool_operand(false); }
        switch node.form {
            case .wildcard_pattern | .binding_pattern: return nil;
            case .literal_pattern(let data):
                let condition = self.temp(self.bool_type());
                var right = self.literal_constant(data.value, data.type_id); var left = value;
                var nil_pattern = false; switch data.value { case .none: nil_pattern = self.types.is_optional(value.type_id()); default: {} }
                if nil_pattern { let tag = self.temp(self.i32_type()); self.emit(MirOp.get_tag(MirGetTagData { result: tag, enum_val: value }));
                    left = self.copy(tag, self.i32_type()); right = self.int_operand("0", self.i32_type());
                } else if self.types.is_string(data.type_id) { let compared = self.temp(self.i32_type());
                    self.static_call(compared, "rt_string_compare", [value, right], self.i32_type());
                    left = self.copy(compared, self.i32_type()); right = self.int_operand("0", self.i32_type());
                }
                self.emit(MirOp.cmp_op(MirCmpOpData { result: condition, op: CmpOpKind.eq(), left, right }));
                return self.copy(condition, self.bool_type());
            case .enum_case_pattern(let data):
                let tag = self.temp(self.i32_type()); self.emit(MirOp.get_tag(MirGetTagData { result: tag, enum_val: value }));
                let local = self.temp(self.bool_type());
                self.emit(MirOp.cmp_op(MirCmpOpData { result: local, op: CmpOpKind.eq(),
                    left: self.copy(tag, self.i32_type()), right: self.int_operand(f"{self.enum_tag(data.enum_type, data.case_name)}", self.i32_type()) }));
                var condition = self.copy(local, self.bool_type());
                if data.payload.len() == 0 { return condition; }
                let result = self.temp(self.bool_type()); let place = self.place(result, self.bool_type()); self.assign(place, condition);
                let payload_bb = self.create_block(); let merge = self.create_block(); self.cond_branch(condition, payload_bb, merge);
                self.switch_to(payload_bb); var index = 0;
                for sub_id in data.payload { var irrefutable = false;
                    if let sub = self.hir.get(sub_id) { switch sub.form { case .wildcard_pattern | .binding_pattern: irrefutable = true; default: {} } }
                    if !irrefutable { if let type_id = self.pattern_type(sub_id, data.enum_type, data.case_name, index) {
                        let payload = self.extract_payload(value, data.case_name, index, type_id);
                        if let test = self.pattern_match(payload, sub_id) { condition = self.pattern_boolean(condition, test, true); }
                    } } index += 1;
                }
                self.assign(place, condition); self.branch(merge); self.switch_to(merge); return self.copy(result, self.bool_type());
            case .or_pattern(let data):
                if data.patterns.len() == 0 { return self.bool_operand(false); }
                var result: MirOperand? = nil;
                for alternative in data.patterns { guard let test = self.pattern_match(value, alternative) else { return nil; }
                    if let previous = result { result = self.pattern_boolean(previous, test, false); } else { result = test; }
                } return result;
            case .tuple_pattern(let data): var result: MirOperand? = nil; var index = 0;
                for element in data.elements { if let field = self.tuple_field(data.type_id, index) { let local = self.temp(field.type_id);
                    self.emit(MirOp.extract_field(MirExtractFieldData { result: local, aggregate: value, field_name: field.name,
                        field_index: index, result_type: field.type_id }));
                    if let test = self.pattern_match(self.copy(local, field.type_id), element.1) {
                        if let previous = result { result = self.pattern_boolean(previous, test, true); } else { result = test; }
                    }
                } index += 1; } return result;
            default: return self.bool_operand(false);
        }
    }
    def static_call(result: MirLocalId?, name: String, args: Vec<MirOperand>, type_id: TypeId, symbol: SymbolId? = nil) -> Void {
        self.emit(MirOp.call_static(MirCallStaticData { result, func_name: name, func_symbol: symbol, args, result_type: type_id }));
    }
    def literal_constant(value: HirValue, type_id: TypeId) -> MirOperand {
        switch value {
            case .integer(let x): return self.int_operand(x, type_id);
            case .floating(let x): return mir_constant(MirConstantKind.float(), MirScalar.floating(x), type_id);
            case .boolean(let x): return mir_constant(MirConstantKind.bool_type(), MirScalar.boolean(x), type_id);
            case .text(let x): return mir_constant(MirConstantKind.string(), MirScalar.text(x), type_id);
            case .type_id(let x): return self.int_operand(f"{self.types.runtime_type_id(x)}", type_id);
            case .none: return self.nil_operand(type_id);
        }
    }
    def lower_else(id: HirId) -> Void {
        if let node = self.hir.get(id) { switch node.form {
            case .block: self.lower_block(id); case .if_stmt(let data): self.lower_if(data);
            case .if_let(let data): self.lower_if_let(data); default: self.lower_stmt(id);
        } }
    }
    def lower_if_let(data: HirIfLetData) -> Void {
        let value = self.lower_expr(data.scrutinee); let matched = self.create_block(); let merge = self.create_block();
        var other = merge; if let else_id = data.else_block { other = self.create_block(); }
        let tag = self.temp(self.i32_type()); self.emit(MirOp.get_tag(MirGetTagData { result: tag, enum_val: value }));
        var case_tag = 1; var enum_pattern = false;
        if let node = self.hir.get(data.pattern) { switch node.form { case .enum_case_pattern(let pattern):
            if let info = self.types.get_type(value.type_id()) { switch info.data { case .enum_type:
                case_tag = self.enum_tag(value.type_id(), pattern.case_name); enum_pattern = true; default: {}
            } } default: {} } }
        self.terminate(MirTerm.switch_int(MirSwitchIntData { value: self.copy(tag, self.i32_type()),
            cases: [(case_tag.to_string(), matched)], default: other }));
        self.switch_to(matched);
        if enum_pattern { self.bind_pattern(data.pattern, value); }
        else if let inner = self.types.get_optional_inner(value.type_id()) {
            let payload = self.extract_payload(value, "Some", 0, inner); self.bind_pattern(data.pattern, payload);
        }
        self.lower_block(data.then_block); if !self.is_terminated() { self.branch(merge); }
        if let else_id = data.else_block { self.switch_to(other); self.lower_else(else_id); if !self.is_terminated() { self.branch(merge); } }
        self.switch_to(merge);
    }
    def lower_switch(data: HirSwitchData) -> Void {
        let value = self.lower_expr(data.scrutinee); let merge = self.create_block();
        if self.types.is_optional(data.scrutinee_type) { self.lower_optional_switch(value, data.cases, merge); }
        else { self.lower_value_switch(value, data.cases, merge); }
        self.switch_to(merge);
    }
    def lower_value_switch(value: MirOperand, cases: Vec<HirId>, merge: MirBlockId) -> Void {
        for case_id in cases { if let node = self.hir.get(case_id) { switch node.form { case .switch_case(let data):
            if data.is_default { self.lower_block(data.body); if !self.is_terminated() { self.branch(merge); } return; }
            for pair in data.patterns {
                let next = self.create_block(); if let condition = self.pattern_match(value, pair.0) {
                    let matched = self.create_block(); self.cond_branch(condition, matched, next); self.switch_to(matched);
                }
                self.bind_pattern(pair.0, value);
                if let guard_id = pair.1 { let body = self.create_block(); let test = self.lower_expr(guard_id);
                    self.cond_branch(test, body, next); self.switch_to(body);
                }
                self.lower_block(data.body); if !self.is_terminated() { self.branch(merge); } self.switch_to(next);
            }
            default: {}
        } } }
        if !self.is_terminated() { self.branch(merge); }
    }
    def optional_pattern_tag(id: HirId) -> i32? {
        if let node = self.hir.get(id) { switch node.form {
            case .enum_case_pattern(let data): if data.case_name.equals("Some") { return 1; }
                if data.case_name.equals("None") || data.case_name.equals("nil") { return 0; }
            case .literal_pattern(let data): switch data.value { case .none: return 0; default: {} }
            default: {}
        } } nil
    }
    def lower_optional_switch(value: MirOperand, cases: Vec<HirId>, merge: MirBlockId) -> Void {
        for case_id in cases { if let node = self.hir.get(case_id) { switch node.form { case .switch_case(let data):
            var complex = data.patterns.len() > 1;
            for pair in data.patterns {
                if let guard_id = pair.1 { complex = true; }
                if let pattern = self.hir.get(pair.0) { switch pattern.form {
                    case .or_pattern: complex = true;
                    case .enum_case_pattern(let d): for id in d.payload { if let payload = self.hir.get(id) { switch payload.form {
                        case .wildcard_pattern | .binding_pattern: {} default: complex = true;
                    } } }
                    default: {}
                } }
            }
            if complex { self.lower_value_switch(value, cases, merge); return; }
            default: {}
        } } }
        let tag = self.temp(self.i32_type()); self.emit(MirOp.get_tag(MirGetTagData { result: tag, enum_val: value }));
        let arms = Vec<(i32, MirBlockId, HirSwitchCaseData, HirId)>.new();
        var fallback = merge; var default_case: HirSwitchCaseData? = nil; var default_pattern: HirId? = nil;
        let seen = Dict<i32, Bool>.with_capacity(4, 0);
        for case_id in cases { if let node = self.hir.get(case_id) { switch node.form { case .switch_case(let data):
            if data.is_default { if let existing = default_case {} else { fallback = self.create_block(); default_case = data; } continue; }
            for pair in data.patterns { var irrefutable = false;
                if let pattern = self.hir.get(pair.0) { switch pattern.form { case .wildcard_pattern | .binding_pattern: irrefutable = true; default: {} } }
                if irrefutable { if let existing = default_case {} else { fallback = self.create_block(); default_case = data; default_pattern = pair.0; } break; }
                if let tag = self.optional_pattern_tag(pair.0) { if !seen.contains(tag) {
                    seen[tag] = true; arms.push((tag, self.create_block(), data, pair.0)); break;
                } }
            }
            default: {}
        } } }
        let targets = Vec<(String, MirBlockId)>.new(); for arm in arms { targets.push((arm.0.to_string(), arm.1)); }
        self.terminate(MirTerm.switch_int(MirSwitchIntData { value: self.copy(tag, self.i32_type()), cases: targets, default: fallback }));
        for arm in arms { self.switch_to(arm.1);
            if arm.0 == 1 { if let node = self.hir.get(arm.3) { switch node.form { case .enum_case_pattern(let pattern):
                if pattern.payload.len() > 0 { if let inner = self.types.get_optional_inner(value.type_id()) {
                    let payload = self.extract_payload(value, "Some", 0, inner); self.bind_pattern(pattern.payload[0], payload);
                } } default: {} } } }
            for pair in arm.2.patterns { if pair.0 == arm.3 { if let guard_id = pair.1 {
                let test = self.lower_expr(guard_id); let next = self.create_block(); self.cond_branch(test, next, fallback); self.switch_to(next); break;
            } } }
            self.lower_block(arm.2.body); if !self.is_terminated() { self.branch(merge); }
        }
        if let data = default_case { self.switch_to(fallback); if let pattern_id = default_pattern {
            if let node = self.hir.get(pattern_id) { switch node.form { case .binding_pattern: self.bind_pattern(pattern_id, value); default: {} } }
        } self.lower_block(data.body); if !self.is_terminated() { self.branch(merge); } }
    }
    def lower_for(data: HirForData) -> Void {
        let value = self.lower_expr(data.iterable); let header = self.create_block(); let body = self.create_block(); let done = self.create_block();
        let prefix = self.type_prefix(value.type_id());
        if prefix.equals("Dict") || prefix.starts_with("Dict_") { self.lower_dict_for(data, value, header, body, done); self.switch_to(done); return; }
        if prefix.equals("Vec") || prefix.starts_with("Vec_") { self.lower_vec_for(data, value, header, body, done); self.switch_to(done); return; }
        var iterator_type = value.type_id();
        if let method = self.members.get_method(value.type_id(), "__iter__") { if let signature = self.types.get_function_data(method.signature) { iterator_type = signature.return_type; } }
        let iterator = self.temp(iterator_type, "__iter");
        self.emit(MirOp.call_witness(MirCallWitnessData { result: iterator, witness_type: value.type_id(), method_name: "__iter__", args: [value], result_type: iterator_type }));
        self.branch(header); self.switch_to(header);
        var element_type = self.hir_type(data.pattern);
        if let method = self.members.get_method(iterator_type, "__next__") { if let signature = self.types.get_function_data(method.signature) {
            if let inner = self.types.get_optional_inner(signature.return_type) { element_type = inner; }
        } }
        let next_type = self.types.make_optional(element_type); let next = self.temp(next_type, "__next");
        self.emit(MirOp.call_witness(MirCallWitnessData { result: next, witness_type: iterator_type, method_name: "__next__",
            args: [self.copy(iterator, iterator_type)], result_type: next_type }));
        let tag = self.temp(self.i64_type()); self.emit(MirOp.get_tag(MirGetTagData { result: tag, enum_val: self.copy(next, next_type) }));
        let condition = self.temp(self.bool_type()); self.emit(MirOp.cmp_op(MirCmpOpData { result: condition, op: CmpOpKind.ne(),
            left: self.copy(tag, self.i64_type()), right: self.int_operand("0", self.i64_type()) }));
        self.cond_branch(self.copy(condition, self.bool_type()), body, done); self.switch_to(body);
        self.loops.push(MirLoopScope { header, exit: done, defer_depth: self.defer_scopes.len() });
        let element = self.temp(element_type, "__elem"); self.emit(MirOp.extract_enum_payload(MirExtractEnumPayloadData {
            result: element, enum_val: self.copy(next, next_type), case_name: "Some", payload_index: 0, result_type: element_type }));
        self.bind_pattern(data.pattern, self.copy(element, element_type)); self.lower_block(data.body); self.loops.pop();
        if !self.is_terminated() { self.branch(header); } self.switch_to(done);
    }
    // `for x in vec` walks indices, so elements that are themselves optional
    // (Vec<String?>) cannot end the loop early.
    def lower_vec_for(data: HirForData, value: MirOperand, header: MirBlockId, body: MirBlockId, done: MirBlockId) -> Void {
        var element_type = self.hir_type(data.pattern);
        if let info = self.types.get_type(value.type_id()) { switch info.data { case .struct_type(let type_data):
            if type_data.type_args.len() > 0 { element_type = type_data.type_args.get(0); } default: {}
        } }
        let i32_type = self.i32_type(); let prefix = self.type_prefix(value.type_id());
        let vector = self.temp(value.type_id(), "__vec"); self.assign(self.place(vector, value.type_id()), value);
        let index = self.temp(i32_type, "__idx"); let place = self.place(index, i32_type); self.assign(place, self.int_operand("0", i32_type));
        self.branch(header); self.switch_to(header);
        let length = self.temp(i32_type, "__len"); self.static_call(length, prefix + "_len", [self.copy(vector, value.type_id())], i32_type);
        let condition = self.temp(self.bool_type());
        self.emit(MirOp.cmp_op(MirCmpOpData { result: condition, op: CmpOpKind.lt(), left: self.copy(index, i32_type), right: self.copy(length, i32_type) }));
        self.cond_branch(self.copy(condition, self.bool_type()), body, done); self.switch_to(body);
        self.loops.push(MirLoopScope { header, exit: done, defer_depth: self.defer_scopes.len() });
        let element = self.temp(element_type, "__elem");
        self.static_call(element, prefix + "_get", [self.copy(vector, value.type_id()), self.copy(index, i32_type)], element_type);
        // The index advances before the body so `continue` moves on.
        let increment = self.temp(i32_type);
        self.emit(MirOp.bin_op(MirBinOpData { result: increment, op: BinOpKind.add(), left: self.copy(index, i32_type), right: self.int_operand("1", i32_type), result_type: i32_type }));
        self.assign(place, self.copy(increment, i32_type));
        self.bind_pattern(data.pattern, self.copy(element, element_type)); self.lower_block(data.body); self.loops.pop();
        if !self.is_terminated() { self.branch(header); }
    }
    def lower_dict_for(data: HirForData, value: MirOperand, header: MirBlockId, body: MirBlockId, done: MirBlockId) -> Void {
        var key_type = self.hir_type(data.pattern);
        if let info = self.types.get_type(value.type_id()) { switch info.data { case .struct_type(let type_data):
            if type_data.type_args.len() > 0 { key_type = type_data.type_args.get(0); } default: {}
        } }
        let i64_type = self.i64_type(); let ptr_type = self.types.get_builtin("RawPtr") ?? self.void_type();
        let index = self.temp(i64_type, "__idx"); let place = self.place(index, i64_type); self.assign(place, self.int_operand("0", i64_type));
        let length = self.temp(i64_type, "__len"); self.static_call(length, self.type_prefix(value.type_id()) + "_len", [value], i64_type);
        self.branch(header); self.switch_to(header); let condition = self.temp(self.bool_type());
        self.emit(MirOp.cmp_op(MirCmpOpData { result: condition, op: CmpOpKind.lt(), left: self.copy(index, i64_type), right: self.copy(length, i64_type) }));
        self.cond_branch(self.copy(condition, self.bool_type()), body, done); self.switch_to(body);
        self.loops.push(MirLoopScope { header, exit: done, defer_depth: self.defer_scopes.len() });
        let handle = self.temp(ptr_type, "__handle"); self.emit(MirOp.extract_field(MirExtractFieldData { result: handle,
            aggregate: value, field_name: "handle", field_index: 0, result_type: ptr_type }));
        let pointer = self.temp(ptr_type, "__keyptr"); self.static_call(pointer, "rt_dict_key_ptr", [self.copy(handle, ptr_type), self.copy(index, i64_type)], ptr_type);
        let key = self.temp(key_type, "__key"); self.assign(self.place(key, key_type), MirOperand.copy(MirPlace {
            base: pointer, projections: [MirProjection.deref(key_type)], type_id: key_type }));
        self.bind_pattern(data.pattern, self.copy(key, key_type)); self.lower_block(data.body); self.loops.pop();
        if !self.is_terminated() { let increment = self.temp(i64_type); self.emit(MirOp.bin_op(MirBinOpData { result: increment,
            op: BinOpKind.add(), left: self.copy(index, i64_type), right: self.int_operand("1", i64_type), result_type: i64_type }));
            self.assign(place, self.copy(increment, i64_type)); self.branch(header);
        }
    }
    def lower_lambda(data: HirLambdaData, location: HirLocation? = nil) -> MirOperand {
        let outer = Dict<i32, TypeId>.with_capacity(16, 0);
        for local in self.locals { if let sid = local.symbol_id { outer[sid.id] = local.type_id; } }
        let captures = analyze_captures(self.hir, data, outer, self.symbols);
        // Reassigned captured `var`s are shared through cells and other bindings are immutable,
        // so an assignment to a captured local here means boxing missed it.
        for id in self.hir.preorder(data.body) { if let node = self.hir.get(id) { switch node.form { case .assign(let assign): if let target = self.hir.get(assign.target) { switch target.form {
            case .var_ref(let ref): for capture in captures { if capture.symbol_id == ref.symbol_id {
                self.errors.push(internal_compiler_error(f"closure assigns captured variable '{capture.name}' that is not in a cell"));
            } }
            default: {}
        } } default: {} } } }
        let name = f"__lambda_{self.func.symbol_id.id}_{self.func.name}_{self.next_value_id}"; self.next_value_id += 1;
        let capture_values = Vec<MirOperand>.new(); let capture_types = Vec<TypeId>.new();
        for capture in captures { if let local = self.bindings[capture.symbol_id.id] {
            capture_values.push(self.copy(local, capture.type_id)); capture_types.push(capture.type_id);
        } }
        let params = Vec<TypeId>.new(); for id in data.params { params.push(self.hir_type(id)); }
        var return_type = self.void_type(); if let signature = self.types.get_function_data(data.type_id) { return_type = signature.return_type; }
        var is_async = false; if let signature = self.types.get_function_data(data.type_id) { is_async = signature.is_async; }
        let closure_type = self.types.make_closure(params, return_type, capture_types, is_async);
        self.pending_lambdas.push(MirPendingLambda { name, lambda: data, captures, closure_type, location: location ?? self.location });
        var entry = name; if is_async { entry = name + "$start"; }
        let result = self.temp(closure_type); self.emit(MirOp.make_closure(MirMakeClosureData {
            result, func_name: entry, captures: capture_values, result_type: closure_type })); self.copy(result, closure_type)
    }
    def lower_var(data: HirVarData) -> MirOperand {
        if let local = self.bindings[data.symbol_id.id] { return self.copy(local, self.locals[local.id].type_id); }
        if let symbol = self.symbols.get_symbol(data.symbol_id) { switch symbol.kind { case .function | .extern_func:
            if let signature = self.types.get_function_data(data.type_id) {
                if signature.is_async {
                    // An async function value is a closure over a starter that spawns the call.
                    let target = abi_async_name(data.symbol_id, data.name, self.symbols, self.types);
                    let closure_type = self.types.make_closure(signature.params.to_vec(), signature.return_type, Vec<TypeId>.new(), true);
                    let starter = target + "$start";
                    self.pending_starters.push(mir_async_starter(starter, target, closure_type, signature.params, self.types));
                    let result = self.temp(closure_type);
                    self.emit(MirOp.make_closure(MirMakeClosureData { result, func_name: starter, captures: Vec<MirOperand>.new(), result_type: closure_type }));
                    return self.copy(result, closure_type);
                }
                if let decl_id = symbol.decl_node { if let node = self.ast.get(decl_id) { switch node.form { case .func_decl(let decl):
                    if decl.is_unsafe { self.errors.push("Unsafe function values require a wrapper with an explicit unsafe block"); return self.nil_operand(data.type_id); }
                    if decl.generic_params.len() > 0 { self.errors.push("Generic function values require a non-generic wrapper"); return self.nil_operand(data.type_id); }
                    default: {}
                } } }
                let params = Vec<HirId>.new(); let arguments = Vec<(String?, HirId)>.new(); var index = 0;
                for type_id in signature.params.to_vec() { let param = self.symbols.create_symbol(f"__arg_{index}", SymbolKind.parameter(), Namespace.value());
                    params.push(self.hir.add(HirForm.param(HirParamData { name: param.name, symbol_id: param.id, type_id, external_name: nil, has_default: false })));
                    let label: String? = nil;
                    arguments.push((label, self.hir.add(HirForm.var_ref(HirVarData { name: param.name, symbol_id: param.id, type_id })))); index += 1;
                }
                let callee = self.hir.add(HirForm.var_ref(data)); let call = self.hir.add(HirForm.call(HirCallData { type_id: signature.return_type, callee, arguments, callee_symbol: data.symbol_id }));
                let body = self.hir.add(HirForm.block(HirBlockData { statements: [self.hir.add(HirForm.return_stmt(HirReturnData { value: call }))] }));
                return self.lower_lambda(HirLambdaData { type_id: data.type_id, params, body, captures: Vec<SymbolId>.new() });
            }
            default: {}
        } }
        self.errors.push(internal_compiler_error("Undefined variable: " + data.name)); self.nil_operand(data.type_id)
    }
    def lower_unary(data: HirUnaryOpData) -> MirOperand {
        if data.op.equals("spawn") {
            self.lower_expr(data.operand);
            if let block = self.current_block() { if block.ops.len() > 0 { let last = block.ops.pop(); switch last {
                case .call_static(let call):
                    if call.func_name.equals("__rolang_await_started_task") && call.args.len() == 1 {
                        // A call through an async function value already started its task.
                        let result = self.temp(data.type_id); self.emit(MirOp.make_struct(MirMakeStructData { result, struct_type: data.type_id,
                            fields: [("handle", call.args[0])] })); return self.copy(result, data.type_id);
                    }
                    let ptr_type = self.types.get_builtin("RawPtr") ?? self.void_type(); let handle = self.temp(ptr_type);
                    self.emit(MirOp.task_spawn(MirTaskSpawnData { result: handle, async_func_name: call.func_name, args: call.args, result_type: ptr_type, frame: nil }));
                    let result = self.temp(data.type_id); self.emit(MirOp.make_struct(MirMakeStructData { result, struct_type: data.type_id,
                        fields: [("handle", self.copy(handle, ptr_type))] })); return self.copy(result, data.type_id);
                default: {}
            } } }
            self.errors.push("spawn currently requires a statically resolved async call"); return mir_unit(data.type_id);
        }
        let operand = self.lower_expr(data.operand);
        if data.op.equals("await") {
            let prefix = self.type_prefix(operand.type_id());
            if prefix.equals("Task") || prefix.starts_with("Task_") {
                let ptr_type = self.types.get_builtin("RawPtr") ?? self.void_type(); let handle = self.temp(ptr_type);
                self.emit(MirOp.extract_field(MirExtractFieldData { result: handle, aggregate: operand, field_name: "handle", field_index: 0, result_type: ptr_type }));
                var result: MirLocalId? = nil; if data.type_id != self.void_type() { result = self.temp(data.type_id); }
                self.static_call(result, "__rolang_await_task", [self.copy(handle, ptr_type)], data.type_id);
                // Releasing a Task cancels it, so the awaited value stays alive until the
                // await resumes: this later read makes it cross the suspension.
                let alive = self.temp(ptr_type);
                self.emit(MirOp.extract_field(MirExtractFieldData { result: alive, aggregate: operand, field_name: "handle", field_index: 0, result_type: ptr_type }));
                if let local = result { return self.copy(local, data.type_id); } return mir_unit(data.type_id);
            }
            let value = self.coerce(operand, data.type_id); self.emit(MirOp.task_yield()); return value;
        }
        let result = self.temp(data.type_id); if let op = unary_op(data.op) {
            self.emit(MirOp.unary_op(MirUnaryOpData { result, op, operand, result_type: data.type_id }));
        } else { self.errors.push(internal_compiler_error("Unknown unary operator: " + data.op)); } self.copy(result, data.type_id)
    }
    def lower_optional_match(data: HirOptionalMatchData) -> MirOperand {
        let value = self.lower_expr(data.scrutinee); let result = self.temp(data.type_id); let place = self.place(result, data.type_id);
        let some = self.create_block(); let none = self.create_block(); let merge = self.create_block(); let tag = self.temp(self.i32_type());
        self.emit(MirOp.get_tag(MirGetTagData { result: tag, enum_val: value })); self.terminate(MirTerm.switch_int(MirSwitchIntData {
            value: self.copy(tag, self.i32_type()), cases: [("1", some)], default: none }));
        self.switch_to(some); let payload = self.create_local("__some_val", data.inner_type, false, false, data.some_binding);
        self.emit(MirOp.extract_enum_payload(MirExtractEnumPayloadData { result: payload, enum_val: value, case_name: "Some", payload_index: 0, result_type: data.inner_type }));
        let yes = self.coerce(self.lower_expr(data.some_expr), data.type_id); self.assign(place, yes); self.branch(merge);
        self.switch_to(none); let no = self.coerce(self.lower_expr(data.none_expr), data.type_id); self.assign(place, no); self.branch(merge);
        self.switch_to(merge); self.copy(result, data.type_id)
    }
    def lower_try(data: HirTryExprData) -> MirOperand {
        let value = self.lower_expr(data.expr); let result = self.temp(data.result_type, "__try_ok"); let tag = self.temp(self.i32_type());
        self.emit(MirOp.get_tag(MirGetTagData { result: tag, enum_val: value })); let test = self.temp(self.bool_type());
        var ok_tag = 1; if let error = data.error_type { ok_tag = self.enum_tag(self.hir_type(data.expr), "ok"); }
        self.emit(MirOp.cmp_op(MirCmpOpData { result: test, op: CmpOpKind.eq(), left: self.copy(tag, self.i32_type()), right: self.int_operand(ok_tag.to_string(), self.i32_type()) }));
        let ok = self.create_block(); let failed = self.create_block(); let merge = self.create_block(); self.cond_branch(self.copy(test, self.bool_type()), ok, failed);
        self.switch_to(failed); let returned = self.temp(self.func.return_type);
        if let error_type = data.error_type { let error = self.extract_payload(value, "err", 0, error_type);
            self.emit(MirOp.make_enum(MirMakeEnumData { result: returned, enum_type: self.func.return_type, case_name: "err",
                tag: self.enum_tag(self.func.return_type, "err"), payload: [error] }));
        } else { self.emit(MirOp.make_none(MirMakeNoneData { result: returned, result_type: self.func.return_type })); }
        self.emit_defers(); self.return_term(self.copy(returned, self.func.return_type)); self.switch_to(ok);
        var name = "Some"; if let error_type = data.error_type { name = "ok"; }
        self.emit(MirOp.extract_enum_payload(MirExtractEnumPayloadData { result, enum_val: value, case_name: name, payload_index: 0, result_type: data.result_type }));
        self.branch(merge); self.switch_to(merge); self.copy(result, data.result_type)
    }
    def lower_type_check(data: HirTypeCheckData) -> MirOperand {
        let type_id = self.hir_type(data.expr); if type_id == data.checked_type { return self.bool_operand(true); }
        if let inner = self.types.get_optional_inner(type_id) { if inner == data.checked_type {
            let value = self.lower_expr(data.expr); let result = self.temp(self.bool_type()); let tag = self.temp(self.i64_type());
            self.emit(MirOp.get_tag(MirGetTagData { result: tag, enum_val: value })); self.emit(MirOp.cmp_op(MirCmpOpData {
                result, op: CmpOpKind.ne(), left: self.copy(tag, self.i64_type()), right: self.int_operand("0", self.i64_type()) })); return self.copy(result, self.bool_type());
        } }
        if let info = self.types.get_type(type_id) { switch info.data { case .existential(let existential):
            let value = self.lower_expr(data.expr); let result = self.temp(self.bool_type());
            self.emit(MirOp.existential_check_type(MirExistentialCheckTypeData { result, existential: value,
                concrete_type: data.checked_type, protocol_type: existential.protocol_id })); return self.copy(result, self.bool_type()); default: {}
        } } self.bool_operand(false)
    }
    def lower_downcast(data: HirCastData) -> MirOperand {
        let value = self.lower_expr(data.expr); var protocol_type = self.types.error_type;
        if let info = self.types.get_type(value.type_id()) { switch info.data { case .existential(let existential): protocol_type = existential.protocol_id; default: {} } }
        if self.types.is_error(protocol_type) { self.errors.push(internal_compiler_error("runtime downcast source is not an existential")); return self.copy(self.temp(data.type_id), data.type_id); }
        var concrete = data.target_type; if data.kind.equals("optional") { concrete = self.types.get_optional_inner(data.type_id) ?? concrete; }
        let test = self.temp(self.bool_type(), "__cast_match"); self.emit(MirOp.existential_check_type(MirExistentialCheckTypeData { result: test,
            existential: value, concrete_type: concrete, protocol_type }));
        let result = self.temp(data.type_id, "__cast_result"); let place = self.place(result, data.type_id);
        let yes = self.create_block(); let no = self.create_block(); let merge = self.create_block(); self.cond_branch(self.copy(test, self.bool_type()), yes, no);
        self.switch_to(yes); let unboxed = self.temp(concrete, "__cast_unboxed"); self.emit(MirOp.existential_unbox(MirExistentialUnboxData {
            result: unboxed, existential: value, concrete_type: concrete, protocol_type, result_type: concrete }));
        if data.kind.equals("optional") { let some = self.temp(data.type_id, "__cast_some"); self.emit(MirOp.make_some(MirMakeSomeData {
            result: some, value: self.copy(unboxed, concrete), result_type: data.type_id })); self.assign(place, self.copy(some, data.type_id));
        } else { self.assign(place, self.copy(unboxed, concrete)); } self.branch(merge); self.switch_to(no);
        if data.kind.equals("optional") { let none = self.temp(data.type_id, "__cast_none"); self.emit(MirOp.make_none(MirMakeNoneData { result: none, result_type: data.type_id }));
            self.assign(place, self.copy(none, data.type_id)); self.branch(merge);
        } else { self.static_call(nil, "rt_panic_invalid_cast", Vec<MirOperand>.new(), self.void_type()); self.terminate(MirTerm.unreachable()); }
        self.switch_to(merge); self.copy(result, data.type_id)
    }
    pub def lower_expr(id: HirId) -> MirOperand {
        guard let node = self.hir.get(id) else { return self.nil_operand(self.types.error_type); }
        switch node.form {
            case .literal(let data): return self.lower_literal(data);
            case .var_ref(let data): return self.lower_var(data);
            case .binary_op(let data): return self.lower_binary(data);
            case .unary_op(let data): return self.lower_unary(data);
            case .ternary(let data): return self.lower_ternary(data);
            case .call(let data): return self.lower_call(data);
            case .method_call(let data): return self.lower_method_call(data);
            case .field_access(let data): return self.lower_field_access(data);
            case .subscript(let data): return self.lower_subscript(data);
            case .tuple(let data): return self.lower_tuple(data);
            case .array(let data): return self.lower_array(data);
            case .dict(let data): return self.lower_dict(data);
            case .struct_init(let data): return self.lower_struct_init(data);
            case .enum_construct(let data): return self.lower_enum_construct(data);
            case .cast(let data):
                if data.kind.equals("optional") || data.kind.equals("forced") {
                    return self.lower_downcast(data);
                }
                let operand = self.lower_expr(data.expr); let result = self.temp(data.target_type);
                self.emit(MirOp.cast_op(MirCastOpData { result, operand, target_type: data.target_type }));
                return self.copy(result, data.target_type);
            case .optional_some(let data):
                let value = self.coerce(self.lower_expr(data.value), data.inner_type); let result = self.temp(data.type_id);
                self.emit(MirOp.make_some(MirMakeSomeData { result, value, result_type: data.type_id }));
                return self.copy(result, data.type_id);
            case .optional_none(let data):
                let result = self.temp(data.type_id); self.emit(MirOp.make_none(MirMakeNoneData { result, result_type: data.type_id }));
                return self.copy(result, data.type_id);
            case .optional_match(let data): return self.lower_optional_match(data);
            case .try_expr(let data): return self.lower_try(data);
            case .type_check(let data): return self.lower_type_check(data);
            case .lambda(let data): return self.lower_lambda(data, self.hir.location(id));
            case .switch_expr(let data):
                let result = self.create_local("__switch_value", data.type_id, false, false, data.result_symbol);
                if self.types.is_heap_type(data.type_id) { self.assign(self.place(result, data.type_id), self.nil_operand(data.type_id)); }
                else { self.default_init(result, data.type_id); }
                if let switch_node = self.hir.get(data.switch) { switch switch_node.form { case .switch_stmt(let switch_data): self.lower_switch(switch_data); default: {} } }
                return self.copy(result, data.type_id);
            case .clone(let data):
                let value = self.lower_expr(data.value); let result = self.temp(data.type_id, "__clone");
                self.emit(MirOp.clone(MirCloneData { result, value, result_type: data.type_id }));
                return self.copy(result, data.type_id);
            default:
                self.errors.push(internal_compiler_error("MIR expression lowering pending: " + node.form.kind()));
                return self.nil_operand(node.form.type_id() ?? self.types.error_type);
        }
    }
}

// A synchronous starter behind an async function value: it spawns `target` with the
// arguments (and, for an async closure, the closure itself first) and returns the task
// handle, which callers await or keep as a Task.
pub def mir_async_starter(name: String, target: String, closure_type: TypeId, params: FrozenVec<TypeId>, types: TypeTable, pass_closure: Bool = false) -> MirFunction {
    let ptr_type = types.get_builtin("RawPtr") ?? types.void_type;
    let locals = Vec<MirLocal>.new(); let args = Vec<MirLocal>.new(); let spawn_args = Vec<MirOperand>.new();
    let closure = MirLocal { id: MirLocalId { id: 0 }, symbol_id: nil, name: "__closure", type_id: closure_type, is_mutable: false, is_arg: true };
    locals.push(closure); args.push(closure);
    if pass_closure { spawn_args.push(mir_copy(closure.id, closure_type)); }
    for index in 0..<params.len() {
        let arg = MirLocal { id: MirLocalId { id: index + 1 }, symbol_id: nil, name: f"__arg{index}", type_id: params.get(index), is_mutable: false, is_arg: true };
        locals.push(arg); args.push(arg); spawn_args.push(mir_copy(arg.id, arg.type_id));
    }
    let handle = MirLocal { id: MirLocalId { id: locals.len() }, symbol_id: nil, name: "__task", type_id: ptr_type, is_mutable: false, is_arg: false };
    locals.push(handle);
    let entry = MirBlockId { id: 0 }; let blocks = Dict<i32, MirBlock>.with_capacity(1, 0);
    let ops = Vec<MirOp>.new();
    ops.push(MirOp.task_spawn(MirTaskSpawnData { result: handle.id, async_func_name: target, args: spawn_args, result_type: ptr_type, frame: nil }));
    blocks[0] = MirBlock { id: entry, ops, terminator: MirTerm.return_stmt(MirReturnData { value: mir_copy(handle.id, ptr_type) }) };
    MirFunction { name, symbol_id: nil, args, locals, ret_type: ptr_type, blocks, block_order: [entry], entry_block: entry, is_async: false, is_method: false }
}
pub struct MirBuilder {
    pub let mono: MonomorphizationResult;
    pub let errors: Vec<String>;
    let pending: Vec<MirPendingLambda>;
    let starter_names: Dict<String, Bool>;
    let debug: Bool;
    pub static def new(mono: MonomorphizationResult, debug: Bool = false) -> MirBuilder { MirBuilder { mono, errors: Vec<String>.new(), pending: Vec<MirPendingLambda>.new(), starter_names: Dict<String, Bool>.with_capacity(8, 1), debug } }
    def build_function(data: HirFunctionData, functions: Vec<MirFunction>, location: HirLocation? = nil) -> Void {
        let builder = MirFunctionBuilder.new(self.mono.ast, self.mono.arena, self.mono.program, data, self.mono.type_table, self.mono.symbol_table);
        builder.debug = self.debug; builder.location = location;
        functions.push(builder.build());
        for error in builder.errors { self.errors.push(data.name + ": " + error); }
        for lambda in builder.pending_lambdas { self.pending.push(lambda); }
        self.add_starters(builder.pending_starters, functions);
    }
    def add_starters(starters: Vec<MirFunction>, functions: Vec<MirFunction>) -> Void {
        for starter in starters { if !self.starter_names.contains(starter.name) { self.starter_names[starter.name] = true; functions.push(starter); } }
    }
    def build_lambda(pending: MirPendingLambda, functions: Vec<MirFunction>) -> Void {
        let params = Vec<HirId>.new(); params.push(self.mono.arena.add(HirForm.param(HirParamData {
            name: "__closure", symbol_id: SymbolId { id: -1 }, type_id: pending.closure_type, external_name: nil, has_default: false })));
        for id in pending.lambda.params { params.push(id); }
        var return_type = self.mono.type_table.void_type; var is_async = false; var param_types = FrozenVec<TypeId>.empty();
        if let signature = self.mono.type_table.get_function_data(pending.lambda.type_id) { return_type = signature.return_type; is_async = signature.is_async; param_types = signature.params; }
        let data = HirFunctionData { name: pending.name, symbol_id: SymbolId { id: -1 }, params, return_type,
            body: pending.lambda.body, is_async, is_method: false, is_static: false };
        let builder = MirFunctionBuilder.new(self.mono.ast, self.mono.arena, self.mono.program, data, self.mono.type_table, self.mono.symbol_table);
        builder.captures = pending.captures; builder.lambda_mode = true; builder.debug = self.debug; builder.location = pending.location;
        let function = builder.build();
        for error in builder.errors { self.errors.push(error); }
        for child in builder.pending_lambdas { self.build_lambda(child, functions); }
        self.add_starters(builder.pending_starters, functions);
        functions.push(function);
        // An async closure's object points at a starter that passes the closure itself first.
        if is_async { functions.push(mir_async_starter(pending.name + "$start", function.name, pending.closure_type, param_types, self.mono.type_table, true)); }
    }
    def build_method(owner: String, receiver_type: TypeId, method_id: HirId, functions: Vec<MirFunction>) -> Void {
        guard let node = self.mono.arena.get(method_id) else { return; }
        switch node.form {
            case .function(let method):
                let params = Vec<HirId>.new();
                if !method.is_static {
                    var self_symbol = SymbolId { id: -1 };
                    if let body = method.body {
                        for id in self.mono.arena.preorder(body) { if let candidate = self.mono.arena.get(id) {
                            switch candidate.form { case .var_ref(let variable):
                                if self_symbol.id < 0 && variable.name.equals("self") { self_symbol = variable.symbol_id; }
                                default: {}
                            }
                        } }
                    }
                    params.push(self.mono.arena.add(HirForm.param(HirParamData { name: "self", symbol_id: self_symbol,
                        type_id: receiver_type, external_name: nil, has_default: false })));
                }
                for param in method.params { params.push(param); }
                var name = method.name;
                if !name.starts_with(owner + "_") { name = owner + "_" + name; }
                self.build_function(HirFunctionData { name, symbol_id: method.symbol_id, params,
                    return_type: method.return_type, body: method.body, is_async: method.is_async,
                    is_method: true, is_static: method.is_static }, functions, self.mono.arena.location(method_id));
            default: self.errors.push(internal_compiler_error("Expected HIR method"));
        }
    }
    def type_name(type_id: TypeId) -> String {
        if let info = self.mono.type_table.get_type(type_id) { switch info.data {
            case .struct_type(let data): if let id = data.symbol_id {
                if let symbol = self.mono.symbol_table.get_symbol(id) { return symbol.name; }
            }
            case .enum_type(let data): if let symbol = self.mono.symbol_table.get_symbol(data.symbol_id) { return symbol.name; }
            case .primitive(let primitive): return primitive.spelling();
            default: {}
        } }
        "Unknown"
    }
    pub def build() -> MirBuildResult {
        let functions = Vec<MirFunction>.new(); let structs = Vec<MirStruct>.new();
        let enums = Vec<MirEnum>.new(); let externs = Vec<MirExternFunc>.new();
        if let root = self.mono.arena.get(self.mono.program) { switch root.form {
            case .program(let program): for id in program.items {
                guard let node = self.mono.arena.get(id) else { continue; }
                switch node.form {
                    case .function(let data): self.build_function(data, functions, self.mono.arena.location(id));
                    case .extern_func(let data):
                        let params = Vec<(String, TypeId)>.new();
                        for param in data.params { if let p = self.mono.arena.get(param) { switch p.form {
                            case .param(let value): params.push((value.name, value.type_id)); default: {}
                        } } }
                        externs.push(MirExternFunc { name: data.name, symbol_id: data.symbol_id, abi: data.abi,
                            params, ret_type: data.return_type });
                    case .struct_type(let data):
                        let fields = Vec<MirField>.new();
                        for field_id in data.fields { if let field = self.mono.arena.get(field_id) { switch field.form {
                            case .field(let value): fields.push(MirField { name: value.name, type_id: value.type_id,
                                is_mutable: value.is_mutable });
                            default: {}
                        } } }
                        let type_id = self.mono.type_table.make_struct(data.symbol_id);
                        structs.push(MirStruct { name: data.name, symbol_id: data.symbol_id, fields, type_id });
                        for method in data.methods { self.build_method(data.name, type_id, method, functions); }
                    case .enum_type(let data):
                        let cases = Vec<MirEnumCase>.new(); var tag = 0;
                        for case_id in data.cases { if let item = self.mono.arena.get(case_id) { switch item.form {
                            case .enum_case(let value): cases.push(MirEnumCase { name: value.name, tag,
                                payload_types: value.payload }); tag += 1;
                            default: {}
                        } } }
                        let type_id = self.mono.type_table.make_enum(data.symbol_id);
                        enums.push(MirEnum { name: data.name, symbol_id: data.symbol_id, cases, type_id });
                        for method in data.methods { self.build_method(data.name, type_id, method, functions); }
                    case .extension(let data):
                        let owner = self.type_name(data.extended_type);
                        for method in data.methods { self.build_method(owner, data.extended_type, method, functions); }
                    default: {}
                }
            }
            default: self.errors.push(internal_compiler_error("Expected HIR program"));
        } }
        for lambda in self.pending { self.build_lambda(lambda, functions); }
        let result = MirProgram { functions, structs, enums, externs };
        for error in validate_mir_program(result) { self.errors.push(error); }
        MirBuildResult { program: result, type_table: self.mono.type_table, symbol_table: self.mono.symbol_table, errors: self.errors }
    }
}
