pub import "mir_analysis.rl"

def mir_next_local(func: MirFunction) -> i32 { var next = 0; for local in func.locals { if local.id.id >= next { next = local.id.id+1; } } next }
def mir_scalar(type_id: TypeId, types: TypeTable) -> Bool { types.is_integer(type_id) || types.is_float(type_id) || types.is_bool(type_id) }
def mir_scalar_structs(program: MirProgram, types: TypeTable) -> Dict<i32, MirStruct> {
    let out = Dict<i32, MirStruct>.with_capacity(16, 0);
    for item in program.structs { var qualifies = false; if let info = types.get_type(item.type_id) { switch info.data { case .struct_type: qualifies = item.fields.len() > 0; default: {} } }
        for field in item.fields { if !mir_scalar(field.type_id, types) { qualifies = false; } }
        for func in program.functions { if func.name.equals(item.name+"___release__") || func.name.equals(item.name+"___gc_trace__") { qualifies = false; } }
        if qualifies { out[item.type_id.id] = item; }
    } out
}
def mir_scalarish(type_id: TypeId, types: TypeTable, structs: Dict<i32, MirStruct>) -> Bool { mir_scalar(type_id, types) || structs.contains(type_id.id) || type_id == types.void_type }
def mir_inline_key(name: String, symbol: SymbolId?) -> String {
    if let id = symbol { return name + "#" + id.id.to_string(); } name
}
def mir_inline_candidates(program: MirProgram, types: TypeTable, structs: Dict<i32, MirStruct>) -> Dict<String, MirFunction> {
    let out = Dict<String, MirFunction>.with_capacity(16, 1);
    let counts = Dict<String, i32>.with_capacity(16, 1);
    for func in program.functions { counts[func.name] = (counts[func.name] ?? 0) + 1; }
    for func in program.externs { counts[func.name] = (counts[func.name] ?? 0) + 1; }
    for func in program.functions {
        if func.is_async || func.block_order.len() != 1 || !mir_scalarish(func.ret_type, types, structs) { continue; }
        guard let block = func.get_block(func.entry_block) else { continue; }
        if block.ops.len() > 48 { continue; }
        var qualifies = false; if let term = block.terminator { switch term { case .return_stmt: qualifies = true; default: {} } }
        for local in func.locals { if !mir_scalarish(local.type_id, types, structs) { qualifies = false; } }
        for op in block.ops { switch op {
            case .suspend: qualifies = false;
            case .call_static(let d): if d.func_name.equals(func.name) { qualifies = false; }
            case .cast_op(let d): if let p = mir_operand_place(d.operand) { if p.projections.len() == 0 && types.format_type(d.target_type).equals("RawPtr") { qualifies = false; } }
            default: {}
        } }
        if qualifies {
            if let symbol = func.symbol_id { out[mir_inline_key(func.name, symbol)] = func; }
            if (counts[func.name] ?? 0) == 1 { out[func.name] = func; }
        }
    } out
}
def mir_inline(func: MirFunction, candidates: Dict<String, MirFunction>) -> Bool {
    var changed = false; var next = mir_next_local(func);
    for id in func.block_order { if let block = func.get_block(id) { let ops = Vec<MirOp>.new(); for op in block.ops {
        var inlined = false; switch op { case .call_static(let call):
        var target = candidates[mir_inline_key(call.func_name, call.func_symbol)];
        if let known = target {} else { target = candidates[call.func_name]; }
        if let callee = target {
            if !mir_inline_key(callee.name, callee.symbol_id).equals(mir_inline_key(func.name, func.symbol_id)) && callee.args.len() == call.args.len() {
                if let body = callee.get_block(callee.entry_block) { let rewriter = MirRewriter.new();
                    for local in callee.locals { let id = MirLocalId { id: next }; next += 1; rewriter.locals[local.id.id] = id;
                        func.locals.push(MirLocal { id, symbol_id: nil, name: f"__inl_{callee.name}_{local.name}", type_id: local.type_id, is_mutable: true, is_arg: false });
                    }
                    var index = 0; for arg in callee.args { ops.push(MirOp.assign(MirAssignData { place: MirPlace { base: rewriter.local(arg.id), projections: Vec<MirProjection>.new(), type_id: arg.type_id }, value: call.args[index] })); index += 1; }
                    for body_op in body.ops { ops.push(rewriter.op(body_op)); }
                    if let result = call.result { if let term = body.terminator { switch term { case .return_stmt(let d): if let value = d.value {
                        ops.push(MirOp.assign(MirAssignData { place: MirPlace { base: result, projections: Vec<MirProjection>.new(), type_id: call.result_type }, value: rewriter.operand(value) }));
                    } default: {} } } }
                    changed = true; inlined = true;
                }
            }
        } default: {} }
        if !inlined { ops.push(op); }
    } block.ops = ops; } } changed
}
def mir_bare_local(value: MirOperand) -> MirLocalId? { if let p = mir_operand_place(value) { if p.projections.len() == 0 { return p.base; } } nil }
def mir_single_field(place: MirPlace) -> String? { if place.projections.len() == 1 { switch place.projections[0] { case .field(let name, _): return name; default: {} } } nil }
struct MirSroa {
    let func: MirFunction; let types: TypeTable; let structs: Dict<i32, MirStruct>;
    let cands: Dict<i32, MirLocal>; let parent: Dict<i32, i32>; let written: MirLocalSet;
    def find(id: i32) -> i32 { var current = id; while (self.parent[current] ?? current) != current { current = self.parent[current] ?? current; } current }
    def union(a: i32, b: i32) -> Void { let left = self.find(a); let right = self.find(b); if left != right { if left == -1 { self.parent[right] = left; } else { self.parent[left] = right; } } }
    def disqualify(id: MirLocalId) -> Void { if self.cands.contains(id.id) { self.union(id.id, -1); } }
    def walk_place(place: MirPlace, read: Bool) -> Void {
        if self.cands.contains(place.base.id) { var allowed = false; if read { if let name = mir_single_field(place) { allowed = true; } } if !allowed { self.disqualify(place.base); } }
        for proj in place.projections { switch proj { case .index(let index, _): self.walk_operand(index); default: {} } }
    }
    def walk_operand(value: MirOperand) -> Void { if let place = mir_operand_place(value) { self.walk_place(place, true); } }
    def walk_op(op: MirOp) -> Void {
        for value in mir_op_operands(op) { self.walk_operand(value); } for place in mir_op_places(op) { self.walk_place(place, false); }
        if let result = mir_op_result(op) { self.disqualify(result); }
    }
    def assign_like(place: MirPlace, value: MirOperand) -> Void {
        if self.cands.contains(place.base.id) {
            if place.projections.len() == 0 { if let src = mir_bare_local(value) { if self.cands.contains(src.id) { self.union(place.base.id, src.id); return; } }
                self.disqualify(place.base); self.walk_operand(value); return;
            }
            if let name = mir_single_field(place) { self.written.add(place.base); self.walk_operand(value); return; }
            self.disqualify(place.base);
        }
        self.walk_operand(value); for proj in place.projections { switch proj { case .index(let index, _): self.walk_operand(index); default: {} } }
    }
    def analyze() -> MirLocalSet {
        for id in self.func.block_order { if let block = self.func.get_block(id) {
            for op in block.ops { switch op {
                case .extract_field(let d): self.disqualify(d.result); if let base = mir_bare_local(d.aggregate) { if self.cands.contains(base.id) { continue; } } self.walk_operand(d.aggregate);
                case .make_struct(let d): if self.cands.contains(d.result.id) { for field in d.fields { self.walk_operand(field.1); } } else { self.walk_op(op); }
                case .assign(let d): self.assign_like(d.place, d.value);
                case .store(let d): self.assign_like(d.place, d.value);
                case .load(let d): if self.cands.contains(d.place.base.id) {
                    if let name = mir_single_field(d.place) { continue; }
                    if d.place.projections.len() == 0 && self.cands.contains(d.result.id) { self.union(d.result.id, d.place.base.id); }
                    else { self.disqualify(d.place.base); }
                } else { self.walk_op(op); }
                default: self.walk_op(op);
            } }
            if let term = block.terminator { for value in mir_term_operands(term) { self.walk_operand(value); } }
        } }
        let counts = Dict<i32, i32>.with_capacity(16, 0); let writes = Dict<i32, Bool>.with_capacity(16, 0);
        for entry in self.cands.entries() { let root = self.find(entry.key); counts[root] = (counts[root] ?? 0)+1; if self.written.contains(entry.value.id) { writes[root] = true; } }
        let qualified = MirLocalSet.new(); for entry in self.cands.entries() { let root = self.find(entry.key);
            if root != self.find(-1) && !((counts[root] ?? 0) > 1 && (writes[root] ?? false)) { qualified.add(entry.value.id); }
        } qualified
    }
    def zero(type_id: TypeId) -> MirOperand {
        if self.types.is_float(type_id) { return mir_constant(MirConstantKind.float(), MirScalar.floating(0.0), type_id); }
        if self.types.is_bool(type_id) { return mir_constant(MirConstantKind.bool_type(), MirScalar.boolean(false), type_id); }
        mir_constant(MirConstantKind.int(), MirScalar.integer("0"), type_id)
    }
    def scalar_assign(ops: Vec<MirOp>, rewriter: MirRewriter, base: MirLocalId, name: String, value: MirOperand) -> Void {
        if let place = rewriter.fields[f"{base.id}:{name}"] { ops.push(MirOp.assign(MirAssignData { place, value: rewriter.operand(value) })); }
    }
    def copy_fields(ops: Vec<MirOp>, rewriter: MirRewriter, dst: MirLocalId, src: MirLocalId) -> Void {
        if let local = self.cands[dst.id] { if let def = self.structs[local.type_id.id] { for field in def.fields {
            if let place = rewriter.fields[f"{src.id}:{field.name}"] { self.scalar_assign(ops, rewriter, dst, field.name, MirOperand.copy(place)); }
        } } }
    }
    def rewrite(qualified: MirLocalSet) -> Void {
        var next = mir_next_local(self.func); let rewriter = MirRewriter.new();
        for id in qualified.values() { if let local = self.cands[id.id] { if let def = self.structs[local.type_id.id] { for field in def.fields {
            let scalar = MirLocalId { id: next }; next += 1;
            self.func.locals.push(MirLocal { id: scalar, symbol_id: nil, name: local.name+"__"+field.name, type_id: field.type_id, is_mutable: true, is_arg: false });
            rewriter.fields[f"{id.id}:{field.name}"] = MirPlace { base: scalar, projections: Vec<MirProjection>.new(), type_id: field.type_id };
        } } } }
        for id in self.func.block_order { if let block = self.func.get_block(id) { let ops = Vec<MirOp>.new(); for op in block.ops {
            var rewritten = false; switch op {
                case .make_struct(let d): if qualified.contains(d.result) { let provided = Dict<String, Bool>.with_capacity(16, 1);
                    for field in d.fields { self.scalar_assign(ops, rewriter, d.result, field.0, field.1); provided[field.0] = true; }
                    if let def = self.structs[d.struct_type.id] { for field in def.fields { if !provided.contains(field.name) { self.scalar_assign(ops, rewriter, d.result, field.name, self.zero(field.type_id)); } } }
                    rewritten = true;
                }
                case .extract_field(let d): if let base = mir_bare_local(d.aggregate) { if qualified.contains(base) {
                    if let place = rewriter.fields[f"{base.id}:{d.field_name}"] { ops.push(MirOp.assign(MirAssignData { place: MirPlace { base: d.result, projections: Vec<MirProjection>.new(), type_id: d.result_type }, value: MirOperand.copy(place) })); rewritten = true; }
                } }
                case .assign(let d): if qualified.contains(d.place.base) {
                    if d.place.projections.len() == 0 { if let src = mir_bare_local(d.value) { self.copy_fields(ops, rewriter, d.place.base, src); rewritten = true; } }
                    else if let name = mir_single_field(d.place) { self.scalar_assign(ops, rewriter, d.place.base, name, d.value); rewritten = true; }
                }
                case .store(let d): if qualified.contains(d.place.base) {
                    if d.place.projections.len() == 0 { if let src = mir_bare_local(d.value) { self.copy_fields(ops, rewriter, d.place.base, src); rewritten = true; } }
                    else if let name = mir_single_field(d.place) { self.scalar_assign(ops, rewriter, d.place.base, name, d.value); rewritten = true; }
                }
                case .load(let d): if qualified.contains(d.place.base) {
                    if let name = mir_single_field(d.place) { if let source = rewriter.fields[f"{d.place.base.id}:{name}"] {
                        ops.push(MirOp.assign(MirAssignData { place: MirPlace { base: d.result, projections: Vec<MirProjection>.new(), type_id: source.type_id }, value: MirOperand.copy(source) })); rewritten = true;
                    } } else if d.place.projections.len() == 0 && qualified.contains(d.result) { self.copy_fields(ops, rewriter, d.result, d.place.base); rewritten = true; }
                }
                default: {}
            }
            if !rewritten { ops.push(rewriter.op(op)); }
        } block.ops = ops; if let term = block.terminator { block.terminator = rewriter.term(term); } } }
    }
}
pub def optimize_mir(program: MirProgram, types: TypeTable) -> Void {
    let structs = mir_scalar_structs(program, types); var round = 0;
    while round < 3 { let candidates = mir_inline_candidates(program, types, structs); var changed = false;
        for func in program.functions { if !func.is_async { if mir_inline(func, candidates) { changed = true; } } }
        if !changed { break; } round += 1;
    }
    for func in program.functions { if !func.is_async {
        let cands = Dict<i32, MirLocal>.with_capacity(16, 0); let parent = Dict<i32, i32>.with_capacity(16, 0); parent[-1] = -1;
        for local in func.locals { if !local.is_arg && structs.contains(local.type_id.id) { cands[local.id.id] = local; parent[local.id.id] = local.id.id; } }
        let sroa = MirSroa { func, types, structs, cands, parent, written: MirLocalSet.new() }; let qualified = sroa.analyze(); if qualified.len() > 0 { sroa.rewrite(qualified); }
    } }
}
