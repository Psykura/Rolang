pub import "mir_analysis.rl"
import "module_abi.rl"

pub struct MirPostResult {
    pub let program: MirProgram; pub let type_table: TypeTable; pub let symbol_table: SymbolTable;
    pub let frame_structs: Dict<String, String>; pub let errors: Vec<String>;
    pub def has_errors() -> Bool { self.errors.len() > 0 }
}
struct MirAwaitPoint { let block: MirBlockId; let index: i32; let global_index: i32; let call: MirCallStaticData; }
def mir_sorted_blocks(func: MirFunction) -> Vec<MirBlockId> {
    let out = Vec<MirBlockId>.new(); for id in func.block_order { out.push(id); }
    var i = 1; while i < out.len() { var j = i; while j > 0 && out[j].id < out[j-1].id { let old = out[j]; out[j] = out[j-1]; out[j-1] = old; j -= 1; } i += 1; } out
}
def mir_await_points(func: MirFunction, names: Dict<String, MirFunction>) -> Vec<MirAwaitPoint> {
    let out = Vec<MirAwaitPoint>.new(); for id in mir_sorted_blocks(func) { if let block = func.get_block(id) {
        var index = 0; for op in block.ops { switch op { case .call_static(let call):
            if names.contains(call.func_name) || call.func_name.equals("__rolang_await_task") || call.func_name.equals("__rolang_await_started_task") || call.func_name.equals("rt_task_wait_done") {
                out.push(MirAwaitPoint { block: id, index, global_index: out.len(), call });
            } default: {} } index += 1;
        }
    } } out
}
def mir_field_place(base: MirLocalId, name: String, type_id: TypeId) -> MirPlace {
    MirPlace { base, projections: [MirProjection.field(name, type_id)], type_id }
}
def mir_bare_place(base: MirLocalId, type_id: TypeId) -> MirPlace { MirPlace { base, projections: Vec<MirProjection>.new(), type_id } }
def mir_store_args(ops: Vec<MirOp>, frame: MirLocalId, callee: MirFunction, args: Vec<MirOperand>) -> Void {
    var index = 0; for arg in callee.args { if index < args.len() {
        ops.push(MirOp.store(MirStoreData { place: mir_field_place(frame, f"$fLocalId(id={arg.id.id})", arg.type_id), value: args[index] }));
    } index += 1; }
}
struct MirAsyncBuilder {
    let original: MirFunction; let types: TypeTable; let frames: Dict<String, TypeId>; let callees: Dict<String, MirFunction>;
    let frame: MirLocal; let locals: Vec<MirLocal>;
    var next_local: i32; var next_block: i32;
    def local(name: String, type_id: TypeId, mutable: Bool = false) -> MirLocalId {
        let id = MirLocalId { id: self.next_local }; self.next_local += 1;
        self.locals.push(MirLocal { id, symbol_id: nil, name, type_id, is_mutable: mutable, is_arg: false }); id
    }
    def block() -> MirBlockId { let id = MirBlockId { id: self.next_block }; self.next_block += 1; id }
    def ptr_type() -> TypeId { self.types.get_builtin("RawPtr") ?? self.types.void_type }
    def int_type() -> TypeId { self.types.get_builtin("i32") ?? self.types.void_type }
    def field(name: String, type_id: TypeId) -> MirPlace { mir_field_place(self.frame.id, name, type_id) }
    // Only locals live across a suspension move between the frame and the resume
    // function. The frame holds references only while the task is suspended: a
    // loaded field is cleared, so a value is released after its last use rather
    // than when the field is next overwritten or the frame is destroyed.
    def load_locals(ops: Vec<MirOp>, live: MirLocalSet) -> Void {
        for local in self.original.locals { if live.contains(local.id) {
            let field = self.field(f"$fLocalId(id={local.id.id})", local.type_id);
            ops.push(MirOp.assign(MirAssignData { place: mir_bare_place(local.id, local.type_id), value: MirOperand.copy(field) }));
            if self.reference(local.type_id) {
                ops.push(MirOp.store(MirStoreData { place: field, value: mir_constant(MirConstantKind.nil(), MirScalar.none(), local.type_id) }));
            }
        } }
    }
    // Types stored as one nullable object pointer.
    def reference(type_id: TypeId) -> Bool {
        if self.types.is_heap_type(type_id) { return true; }
        if let inner = self.types.get_optional_inner(type_id) { return self.types.is_heap_type(inner); }
        false
    }
    def store_locals(ops: Vec<MirOp>, live: MirLocalSet) -> Void {
        for local in self.original.locals { if live.contains(local.id) { ops.push(MirOp.store(MirStoreData {
            place: self.field(f"$fLocalId(id={local.id.id})", local.type_id), value: mir_copy(local.id, local.type_id)
        })); } }
    }
    // Locals of the original function used after op `index` of `block` before being redefined.
    def live_after(block: MirBlock, index: i32, liveness: Dict<i32, MirBlockLiveness>, tracked: MirLocalSet) -> MirLocalSet {
        let live = MirLocalSet.new();
        if let analysis = liveness[block.id.id] { live.extend(analysis.live_out); }
        if let term = block.terminator { for operand in mir_term_operands(term) { if let local = mir_operand_local(operand) { if tracked.contains(local) { live.add(local); } } } }
        var at = block.ops.len() - 1;
        while at > index {
            let op = block.ops[at];
            if let result = mir_op_result(op) { live.remove(result); }
            for place in mir_op_places(op) {
                var write = false; switch op { case .assign: write = place.projections.len() == 0; default: {} }
                if write { live.remove(place.base); } else if tracked.contains(place.base) { live.add(place.base); }
            }
            for operand in mir_op_operands(op) { if let local = mir_operand_local(operand) { if tracked.contains(local) { live.add(local); } } }
            at -= 1;
        }
        live
    }
    def is_spawn(point: MirAwaitPoint) -> Bool {
        !point.call.func_name.equals("__rolang_await_task") && !point.call.func_name.equals("__rolang_await_started_task") && !point.call.func_name.equals("rt_task_wait_done")
    }
    // The awaiting task owns the child, releasing it when the result is taken: direct async
    // calls, and tasks started through async function values (whose handle has no other owner).
    def owns_child(point: MirAwaitPoint) -> Bool { self.is_spawn(point) || point.call.func_name.equals("__rolang_await_started_task") }
    def await_call(point: MirAwaitPoint, ops: Vec<MirOp>) -> Void {
        let ptr = self.ptr_type(); let task_field = self.field(f"$task{point.global_index}", ptr);
        var handle: MirOperand; var consume = "0";
        if !self.is_spawn(point) { handle = point.call.args[0]; if self.owns_child(point) { consume = "1"; } }
        else {
            let task = self.local(f"_task_res{point.global_index}", ptr, true);
            guard let callee = self.callees[point.call.func_name] else { return; }
            guard let frame_type = self.frames[point.call.func_name] else { return; }
            let child = self.local(f"_child_frame_{point.global_index}", frame_type);
            ops.push(MirOp.alloc_async_frame(MirAllocAsyncFrameData { result: child, frame_type }));
            mir_store_args(ops, child, callee, point.call.args);
            ops.push(MirOp.task_spawn(MirTaskSpawnData { result: task, async_func_name: point.call.func_name,
                args: Vec<MirOperand>.new(), result_type: ptr, frame: mir_copy(child, frame_type) }));
            handle = mir_copy(task, ptr); consume = "1";
        }
        ops.push(MirOp.store(MirStoreData { place: task_field, value: handle }));
        ops.push(MirOp.call_static(MirCallStaticData { result: nil, func_name: "rt_task_wait_on", func_symbol: nil,
            args: [handle, mir_constant(MirConstantKind.int(), MirScalar.integer(consume), self.int_type())], result_type: self.types.void_type }));
    }
    def fixup(point: MirAwaitPoint, ops: Vec<MirOp>) -> Void {
        if point.call.func_name.equals("rt_task_wait_done") { return; }
        let ptr = self.ptr_type(); let handle = self.local(f"_prev_handle_{point.global_index}", ptr);
        ops.push(MirOp.assign(MirAssignData { place: mir_bare_place(handle, ptr), value: MirOperand.copy(self.field(f"$task{point.global_index}", ptr)) }));
        var result: MirLocalId;
        if let id = point.call.result { result = id; } else { result = self.local(f"_void_join_{point.global_index}", self.types.void_type); }
        ops.push(MirOp.task_get_result(MirTaskGetResultData { result, task_handle: mir_copy(handle, ptr), result_type: point.call.result_type, consume: self.owns_child(point) }));
    }
    def resume(points: Vec<MirAwaitPoint>) -> MirFunction {
        let state = self.local("_state", self.int_type(), true);
        for local in self.original.locals { self.locals.push(MirLocal { id: local.id, symbol_id: local.symbol_id, name: local.name,
            type_id: local.type_id, is_mutable: local.is_mutable, is_arg: false }); }
        let segments = Dict<i32, Vec<MirBlockId>>.with_capacity(16, 0); let grouped = Dict<i32, Vec<MirAwaitPoint>>.with_capacity(16, 0);
        let posts = Dict<i32, MirBlockId>.with_capacity(16, 0); let rewriter = MirRewriter.new();
        for point in points { let list = grouped[point.block.id] ?? Vec<MirAwaitPoint>.new(); list.push(point); grouped[point.block.id] = list; }
        let sorted = mir_sorted_blocks(self.original);
        for id in sorted { let list = grouped[id.id] ?? Vec<MirAwaitPoint>.new(); let ids = Vec<MirBlockId>.new();
            var i = 0; while i <= list.len() { ids.push(self.block()); i += 1; }
            segments[id.id] = ids; rewriter.blocks[id.id] = ids[0];
            i = 0; for point in list { posts[point.global_index] = ids[i+1]; i += 1; }
        }
        let fallback = self.block(); let dispatch = MirBlockId { id: 0 };
        // Locals live in the resume function between suspensions; they are copied
        // from the frame when the task starts or resumes and back before it suspends
        // or completes, so the frame holds every value whenever the task is not running.
        let start_block = self.block();
        let blocks = Dict<i32, MirBlock>.with_capacity(16, 0); let order = [dispatch, fallback, start_block];
        let tracked = MirLocalSet.new(); for local in self.original.locals { tracked.add(local.id); }
        let liveness = mir_liveness(self.original, tracked);
        // Locals cross a suspension only while live, as values are released after
        // their last use; an awaited Task is used again after its await resumes.
        let entry_live = MirLocalSet.new();
        if let analysis = liveness[self.original.entry_block.id] { entry_live.extend(analysis.live_in); }
        let start_ops = Vec<MirOp>.new(); self.load_locals(start_ops, entry_live);
        blocks[start_block.id] = MirBlock { id: start_block, ops: start_ops, terminator: MirTerm.branch(MirBranchData { target: rewriter.block(self.original.entry_block) }) };
        let cases = Vec<(String, MirBlockId)>.new(); cases.push(("0", start_block));
        for point in points { if let target = posts[point.global_index] { cases.push((f"{point.global_index+1}", target)); } }
        blocks[0] = MirBlock { id: dispatch, ops: [MirOp.assign(MirAssignData { place: mir_bare_place(state, self.int_type()), value: MirOperand.copy(self.field("$state", self.int_type())) })],
            terminator: MirTerm.switch_int(MirSwitchIntData { value: mir_copy(state, self.int_type()), cases, default: fallback }) };
        blocks[fallback.id] = MirBlock { id: fallback, ops: Vec<MirOp>.new(), terminator: MirTerm.unreachable() };
        for id in sorted { guard let original = self.original.get_block(id) else { continue; }
            guard let ids = segments[id.id] else { continue; }
            let list = grouped[id.id] ?? Vec<MirAwaitPoint>.new(); var seg = 0;
            while seg < ids.len() { let ops = Vec<MirOp>.new();
                var start = 0;
                if seg > 0 {
                    let point = list[seg-1];
                    let live = self.live_after(original, point.index, liveness, tracked);
                    if let result = point.call.result { live.remove(result); }
                    self.load_locals(ops, live); self.fixup(point, ops); start = point.index+1;
                }
                var end = original.ops.len(); if seg < list.len() { end = list[seg].index; }
                while start < end { let op = original.ops[start]; switch op { case .task_yield: {} default: ops.push(op); } start += 1; }
                var term = MirTerm.return_stmt(MirReturnData { value: nil });
                if seg < list.len() { let point = list[seg]; self.await_call(point, ops);
                    ops.push(MirOp.store(MirStoreData { place: self.field("$state", self.int_type()), value: mir_constant(MirConstantKind.int(), MirScalar.integer(f"{point.global_index+1}"), self.int_type()) }));
                    let live = self.live_after(original, point.index, liveness, tracked);
                    if let result = point.call.result { live.remove(result); }
                    self.store_locals(ops, live); ops.push(MirOp.task_yield());
                } else {
                    if let original_term = original.terminator { switch original_term {
                        case .return_stmt(let d):
                            ops.push(MirOp.task_complete(MirTaskCompleteData { task_handle: MirOperand.copy(self.field("$handle", self.ptr_type())), result: d.value }));
                        default: term = rewriter.term(original_term);
                    } }
                }
                blocks[ids[seg].id] = MirBlock { id: ids[seg], ops, terminator: term }; order.push(ids[seg]); seg += 1;
            }
        }
        MirFunction { name: self.original.name+"_resume", symbol_id: nil, args: [self.frame], locals: self.locals, ret_type: self.types.void_type,
            blocks, block_order: order, entry_block: dispatch, is_async: false, is_method: false }
    }
    def entry() -> MirFunction {
        let ptr = self.ptr_type(); let frame_type = self.frame.type_id;
        let frame = self.local("_frame", frame_type); let handle = self.local("_task", ptr); let ret = self.local("_ret", self.original.ret_type);
        let ops = Vec<MirOp>.new(); ops.push(MirOp.alloc_async_frame(MirAllocAsyncFrameData { result: frame, frame_type }));
        let args = Vec<MirOperand>.new(); for arg in self.original.args { args.push(mir_copy(arg.id, arg.type_id)); }
        mir_store_args(ops, frame, self.original, args);
        ops.push(MirOp.task_spawn(MirTaskSpawnData { result: handle, async_func_name: self.original.name, args: Vec<MirOperand>.new(), result_type: ptr, frame: mir_copy(frame, frame_type) }));
        ops.push(MirOp.store(MirStoreData { place: mir_field_place(frame, "$handle", ptr), value: mir_copy(handle, ptr) }));
        ops.push(MirOp.scheduler_run(MirSchedulerRunData { until_handle: mir_copy(handle, ptr), destroy_after: self.original.ret_type == self.types.void_type }));
        var value: MirOperand? = nil;
        if self.original.ret_type != self.types.void_type { ops.push(MirOp.task_get_result(MirTaskGetResultData { result: ret, task_handle: mir_copy(handle, ptr), result_type: self.original.ret_type, consume: true })); value = mir_copy(ret, self.original.ret_type); }
        let id = MirBlockId { id: 0 }; let blocks = Dict<i32, MirBlock>.with_capacity(16, 0);
        blocks[0] = MirBlock { id, ops, terminator: MirTerm.return_stmt(MirReturnData { value }) };
        MirFunction { name: self.original.name, symbol_id: self.original.symbol_id, args: self.original.args, locals: self.locals,
            ret_type: self.original.ret_type, blocks, block_order: [id], entry_block: id, is_async: false, is_method: self.original.is_method }
    }
}
pub def lower_async(result: MirBuildResult) -> MirPostResult {
    let types = result.type_table; let errors = Vec<String>.new(); let frames = Dict<String, TypeId>.with_capacity(16, 1);
    let names = Dict<String, String>.with_capacity(16, 1); let callees = Dict<String, MirFunction>.with_capacity(16, 1);
    let frame_defs = Dict<String, MirStruct>.with_capacity(16, 1); let structs = Vec<MirStruct>.new(); for item in result.program.structs { structs.push(item); }
    for func in result.program.functions { if func.is_async { callees[func.name] = func; } }
    let ptr = types.get_builtin("RawPtr") ?? types.void_type; let int_type = types.get_builtin("i32") ?? types.void_type;
    for func in result.program.functions { if func.is_async {
        let name = func.name+"_Frame"; names[func.name] = name; let symbol = result.symbol_table.create_synthetic_symbol_id(); let type_id = types.make_struct(symbol);
        if result.symbol_table.separate_modules {
            if let original = func.symbol_id { result.symbol_table.module_type_keys[symbol.id] = "frame:" + abi_symbol_key(original, result.symbol_table, types); }
        }
        frames[func.name] = type_id; let fields = [MirField { name: "$state", type_id: int_type, is_mutable: true }, MirField { name: "$handle", type_id: ptr, is_mutable: true }];
        for local in func.locals { fields.push(MirField { name: f"$fLocalId(id={local.id.id})", type_id: local.type_id, is_mutable: true }); }
        for point in mir_await_points(func, callees) { fields.push(MirField { name: f"$task{point.global_index}", type_id: ptr, is_mutable: true }); }
        let def = MirStruct { name, symbol_id: symbol, fields, type_id }; structs.push(def); frame_defs[func.name] = def;
    } }
    // Materialize explicit spawn frames before splitting blocks; the expansion
    // changes operation indices, so await points are collected again below.
    for func in result.program.functions { var next = 1; for local in func.locals { if local.id.id >= next { next = local.id.id+1; } }
        for id in func.block_order { if let block = func.get_block(id) { let ops = Vec<MirOp>.new(); for op in block.ops { switch op {
            case .task_spawn(let d):
                if let existing = d.frame {} else {
                    guard let callee = callees[d.async_func_name] else { errors.push(f"Cannot spawn async external function '{d.async_func_name}'; use an async wrapper"); continue; }
                    guard let frame_type = frames[d.async_func_name] else { continue; }
                    let local = MirLocalId { id: next }; next += 1;
                    func.locals.push(MirLocal { id: local, symbol_id: nil, name: "_spawn_frame", type_id: frame_type, is_mutable: false, is_arg: false });
                    if let def = frame_defs[func.name] {
                        let fields = Vec<MirField>.new(); var index = 0; for field in def.fields {
                            if index == 2+func.locals.len()-1 { fields.push(MirField { name: f"$fLocalId(id={local.id})", type_id: frame_type, is_mutable: true }); } fields.push(field); index += 1;
                        }
                        if index == 2+func.locals.len()-1 { fields.push(MirField { name: f"$fLocalId(id={local.id})", type_id: frame_type, is_mutable: true }); }
                        while def.fields.len() > 0 { def.fields.pop(); } for field in fields { def.fields.push(field); }
                    }
                    ops.push(MirOp.alloc_async_frame(MirAllocAsyncFrameData { result: local, frame_type })); mir_store_args(ops, local, callee, d.args);
                    d.frame = mir_copy(local, frame_type); d.args = Vec<MirOperand>.new();
                }
                ops.push(op); if let frame = d.frame { if let place = mir_operand_place(frame) { ops.push(MirOp.assign(MirAssignData { place, value: mir_constant(MirConstantKind.nil(), MirScalar.none(), place.type_id) })); } }
            default: ops.push(op);
        } } block.ops = ops; } }
    }
    var next_local = 1; var next_block = 1;
    for func in result.program.functions { for local in func.locals { if local.id.id >= next_local { next_local = local.id.id+1; } } for id in func.block_order { if id.id >= next_block { next_block = id.id+1; } } }
    let functions = Vec<MirFunction>.new();
    for func in result.program.functions { if !func.is_async { functions.push(func); continue; }
        guard let frame_type = frames[func.name] else { continue; }
        let points = mir_await_points(func, callees);
        let frame = MirLocal { id: MirLocalId { id: next_local }, symbol_id: nil, name: "_frame", type_id: frame_type, is_mutable: false, is_arg: true };
        let builder = MirAsyncBuilder { original: func, types, frames, callees, frame, locals: [frame], next_local: next_local+1, next_block };
        functions.push(builder.resume(points));
        if points.len() == 0 {
            functions.push(MirFunction { name: func.name, symbol_id: func.symbol_id, args: func.args, locals: func.locals, ret_type: func.ret_type,
                blocks: func.blocks, block_order: func.block_order, entry_block: func.entry_block, is_async: false, is_method: func.is_method });
        } else {
            let locals = Vec<MirLocal>.new(); for arg in func.args { locals.push(arg); }
            let entry = MirAsyncBuilder { original: func, types, frames, callees, frame, locals, next_local, next_block }; functions.push(entry.entry());
        }
    }
    MirPostResult { program: MirProgram { functions, structs, enums: result.program.enums, externs: result.program.externs }, type_table: types, symbol_table: result.symbol_table, frame_structs: names, errors }
}
