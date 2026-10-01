pub import "mir_analysis.rl"

def mir_call_args(op: MirOp) -> Vec<MirOperand>? { switch op {
    case .call_static(let d): d.args; case .call_v_table(let d): d.args;
    case .call_closure(let d): d.args; case .call_witness(let d): d.args; default: nil;
} }
def mir_address_take(op: MirOp, id: MirLocalId, types: TypeTable) -> MirLocalId? {
    switch op { case .cast_op(let data):
        if data.target_type != (types.get_builtin("RawPtr") ?? types.error_type) { return nil; }
        if let place = mir_operand_place(data.operand) { if place.base == id && place.projections.len() == 0 { return data.result; } }
        default: {}
    } nil
}
def mir_pure_outparam(ops: Vec<MirOp>, start: i32, id: MirLocalId, types: TypeTable) -> Bool {
    var pointer: MirLocalId? = nil; var index = start;
    while index < ops.len() { let op = ops[index]; index += 1;
        if let ptr = pointer {
            if mir_references_local(op, id) { return false; }
            if let args = mir_call_args(op) { for arg in args { if let local = mir_operand_local(arg) { if local == ptr { return true; } } } }
            if mir_references_local(op, ptr) { return false; }
        } else { if mir_references_local(op, id) { pointer = mir_address_take(op, id, types); if let ptr = pointer {} else { return false; } } }
    } false
}
pub def elide_outparam_default_init(program: MirProgram, types: TypeTable) -> i32 {
    var total = 0;
    for func in program.functions { for bid in func.block_order { if let block = func.get_block(bid) {
        let ops = block.ops; let rewritten = Vec<MirOp>.new(); var index = 0;
        while index < ops.len() { var elide = false; if index+1 < ops.len() { switch ops[index] { case .alloc_obj(let allocated):
            switch ops[index+1] { case .assign(let init): if init.place.projections.len() == 0 && types.is_heap_type(init.place.type_id) {
                if let value = mir_operand_place(init.value) { if value.projections.len() == 0 && value.base == allocated.result {
                    var unique = true; for other_id in func.block_order { if let other = func.get_block(other_id) { var j = 0; for op in other.ops {
                        if other_id != bid || j != index && j != index+1 { if mir_references_local(op, allocated.result) { unique = false; } } j += 1;
                    } } }
                    if unique && mir_pure_outparam(ops, index+2, init.place.base, types) {
                        rewritten.push(MirOp.assign(MirAssignData { place: init.place, value: mir_constant(MirConstantKind.nil(), MirScalar.none(), init.place.type_id) }));
                        elide = true; total += 1;
                    }
                } }
            } default: {} } default: {} } }
            if elide { index += 2; } else { rewritten.push(ops[index]); index += 1; }
        } block.ops = rewritten;
    } } } total
}
