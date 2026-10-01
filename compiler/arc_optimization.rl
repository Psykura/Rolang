pub import "arc_insertion.rl"

def mir_arc_local(value: MirOperand) -> MirLocalId? { if let p = mir_operand_place(value) { if p.projections.len() == 0 { return p.base; } } nil }
def mir_op_def(op: MirOp) -> MirLocalId? {
    switch op { case .assign(let d): if d.place.projections.len() == 0 { return d.place.base; } return nil;
        case .suspend: return nil; default: return mir_op_result(op); }
}
def mir_op_uses(op: MirOp) -> Vec<MirLocalId> {
    let out = Vec<MirLocalId>.new(); for operand in mir_op_operands(op) { if let local = mir_operand_local(operand) { out.push(local); } }
    for place in mir_op_places(op) { var used = true; switch op { case .assign: used = place.projections.len() > 0; default: {} } if used { out.push(place.base); } } out
}
def mir_arc_op(op: MirOp) -> Bool { switch op { case .retain, .release: true; default: false; } }
def mir_pair_safe(op: MirOp) -> Bool { switch op { case .assign, .load, .store, .bin_op, .cmp_op, .unary_op, .cast_op, .get_tag: true; default: false; } }
def mir_release_motion_safe(op: MirOp) -> Bool { switch op {
    case .assign, .load, .bin_op, .cmp_op, .unary_op, .cast_op, .get_tag, .extract_field, .extract_enum_payload, .extract_closure_capture: true;
    default: false;
} }
def mir_cancel_arc_pairs(func: MirFunction) -> Void {
    for id in func.block_order { if let block = func.get_block(id) {
        let removed = Dict<i32, Bool>.with_capacity(16, 0); var i = 0;
        for op in block.ops { if !removed.contains(i) { switch op { case .retain(let d): if let local = mir_arc_local(d.operand) {
            var j = i+1; var scanned = 0; while j < block.ops.len() && scanned <= 8 {
                if removed.contains(j) { j += 1; continue; }
                let next = block.ops[j]; var stop = false;
                switch next { case .release(let d): if let released = mir_arc_local(d.operand) { if released == local { removed[i] = true; removed[j] = true; } } stop = true;
                    case .retain: stop = true; default: if !mir_pair_safe(next) { stop = true; }
                }
                if let def = mir_op_def(next) { if def == local { stop = true; } }
                if stop { break; } j += 1; scanned += 1;
            }
        } default: {} } } i += 1; }
        let out = Vec<MirOp>.new(); i = 0; for op in block.ops { if !removed.contains(i) { out.push(op); } i += 1; } block.ops = out;
    } }
}
struct MirArcUse { let block: MirBlockId; let index: i32; }
struct MirArcUses { let uses: Vec<MirArcUse>; var definition: MirArcUse?; }
def mir_collect_arc_uses(func: MirFunction, refs: MirLocalSet) -> Dict<i32, MirArcUses> {
    let out = Dict<i32, MirArcUses>.with_capacity(16, 0); for id in refs.values() { out[id.id] = MirArcUses { uses: Vec<MirArcUse>.new(), definition: nil }; }
    for id in func.block_order { if let block = func.get_block(id) { var index = 0; for op in block.ops {
        for local in mir_op_uses(op) { if let info = out[local.id] { info.uses.push(MirArcUse { block: id, index }); } }
        if let local = mir_op_def(op) { if let info = out[local.id] { if let existing = info.definition {} else { info.definition = MirArcUse { block: id, index }; } } }
        index += 1;
    } if let term = block.terminator { for operand in mir_term_operands(term) { if let local = mir_operand_local(operand) { if let info = out[local.id] { info.uses.push(MirArcUse { block: id, index }); } } } } } } out
}
def mir_elide_borrowed_arc(func: MirFunction, refs: MirLocalSet) -> Void {
    let retained = MirLocalSet.new(); for id in func.block_order { if let block = func.get_block(id) { for op in block.ops { switch op { case .retain(let d): if let local = mir_arc_local(d.operand) { retained.add(local); } default: {} } } } }
    let info = mir_collect_arc_uses(func, refs); let borrowed = MirLocalSet.new();
    for local in refs.values() { if !retained.contains(local) { continue; } guard let data = info[local.id] else { continue; }
        let uses = Vec<MirArcUse>.new(); for use in data.uses { if let block = func.get_block(use.block) { if use.index >= block.ops.len() || !mir_arc_op(block.ops[use.index]) { uses.push(use); } } }
        if uses.len() != 1 { continue; } let use = uses[0]; guard let block = func.get_block(use.block) else { continue; }
        if use.index >= block.ops.len() { continue; } var safe = false;
        switch block.ops[use.index] { case .call_static(let d): safe = d.func_name.equals("rt_string_len") || d.func_name.equals("rt_string_char_at") || d.func_name.equals("rt_gvec_len");
            if let result = d.result { if result == local { safe = false; } } default: {} }
        if !safe { continue; } guard let definition = data.definition else { continue; }
        guard let defining = func.get_block(definition.block) else { continue; }
        switch defining.ops[definition.index] { case .extract_field, .extract_enum_payload, .extract_closure_capture, .existential_unbox, .load: borrowed.add(local); default: {} }
    }
    for id in func.block_order { if let block = func.get_block(id) { let out = Vec<MirOp>.new(); for op in block.ops { var remove = false; switch op {
        case .retain(let d): if let local = mir_arc_local(d.operand) { remove = borrowed.contains(local); }
        case .release(let d): if let local = mir_arc_local(d.operand) { remove = borrowed.contains(local); }
        default: {}
    } if !remove { out.push(op); } } block.ops = out; } }
}
def mir_has_use(op: MirOp, local: MirLocalId) -> Bool { for used in mir_op_uses(op) { if used == local { return true; } } false }
def mir_latest_arc_use(block: MirBlock, local: MirLocalId, upper: i32, deleted: Dict<i32, Bool>) -> i32 {
    var latest = -1; var last_def = -1; var index = 0;
    for op in block.ops { if index >= upper { break; }
        if !deleted.contains(index) && (!mir_release_motion_safe(op) || mir_has_use(op, local)) { latest = index; }
        if let def = mir_op_def(op) { if def == local { last_def = index; } } index += 1;
    }
    if block.ops.len() < upper { if let term = block.terminator { for operand in mir_term_operands(term) { if let used = mir_operand_local(operand) { if used == local { latest = block.ops.len(); } } } } }
    if last_def > latest { return -1; } latest
}
def mir_has_def_before(block: MirBlock, local: MirLocalId, upper: i32) -> Bool {
    var index = 0; for op in block.ops { if index >= upper { break; } if let def = mir_op_def(op) { if def == local { return true; } } index += 1; } false
}
def mir_release_target(func: MirFunction, preds: Dict<i32, Vec<MirBlockId>>, deletes: Dict<i32, Dict<i32, Bool>>, local: MirLocalId, source: MirBlockId, index: i32) -> MirArcUse? {
    guard let block = func.get_block(source) else { return nil; }
    guard let removed = deletes[source.id] else { return nil; }
    let latest = mir_latest_arc_use(block, local, index, removed); if latest >= 0 { return MirArcUse { block: source, index: latest+1 }; }
    if mir_has_def_before(block, local, index) { return nil; }
    let visited = Dict<i32, Bool>.with_capacity(16, 0); visited[source.id] = true; var current = source;
    while true { guard let list = preds[current.id] else { return nil; } if list.len() != 1 { return nil; }
        let pred = list[0]; if visited.contains(pred.id) { return nil; } guard let block = func.get_block(pred) else { return nil; }
        guard let term = block.terminator else { return nil; } if mir_targets(term).len() != 1 { return nil; }
        visited[pred.id] = true; guard let removed = deletes[pred.id] else { return nil; }
        let latest = mir_latest_arc_use(block, local, block.ops.len()+1, removed);
        if latest >= 0 { var insert = latest+1; if insert > block.ops.len() { insert = block.ops.len(); } return MirArcUse { block: pred, index: insert }; }
        if mir_has_def_before(block, local, block.ops.len()) { return nil; } current = pred;
    } nil
}
def mir_move_releases(func: MirFunction, refs: MirLocalSet) -> Void {
    let preds = mir_predecessors(func); let deletes = Dict<i32, Dict<i32, Bool>>.with_capacity(16, 0);
    let inserts = Dict<i32, Vec<(i32, MirOp)>>.with_capacity(16, 0);
    for id in func.block_order { deletes[id.id] = Dict<i32, Bool>.with_capacity(16, 0); inserts[id.id] = Vec<(i32, MirOp)>.new(); }
    for id in func.block_order { if let block = func.get_block(id) { var index = 0; for op in block.ops { switch op { case .release(let d):
        if let local = mir_arc_local(d.operand) { if refs.contains(local) { if let target = mir_release_target(func, preds, deletes, local, id, index) {
            if target.block != id || target.index != index { if let removed = deletes[id.id] { removed[index] = true; } if let list = inserts[target.block.id] { list.push((target.index, op)); } }
        } } } default: {} } index += 1; } } }
    for id in func.block_order { if let block = func.get_block(id) { guard let removed = deletes[id.id] else { continue; } guard let added = inserts[id.id] else { continue; }
        let out = Vec<MirOp>.new(); var index = 0; while index <= block.ops.len() {
            for pair in added { if pair.0 == index { out.push(pair.1); } }
            if index < block.ops.len() && !removed.contains(index) { out.push(block.ops[index]); } index += 1;
        } block.ops = out;
    } }
}
pub def optimize_arc_program(program: MirProgram, types: TypeTable) -> Void {
    for func in program.functions { let refs = mir_ref_locals(func, types); if refs.len() == 0 { continue; }
        mir_cancel_arc_pairs(func); mir_elide_borrowed_arc(func, refs); mir_move_releases(func, refs);
    }
}
