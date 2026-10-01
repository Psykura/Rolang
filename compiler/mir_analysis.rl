pub import "mir_utils.rl"

pub def copy_mir_program(program: MirProgram) -> MirProgram {
    let rewriter = MirRewriter.new(); let functions = Vec<MirFunction>.new();
    for func in program.functions {
        let locals = Vec<MirLocal>.new(); for local in func.locals { locals.push(local); }
        let blocks = Dict<i32, MirBlock>.with_capacity(16, 0); let order = Vec<MirBlockId>.new();
        for id in func.block_order { if let block = func.get_block(id) { let ops = Vec<MirOp>.new(); for op in block.ops { ops.push(rewriter.op(op)); }
            var term: MirTerm? = nil; if let value = block.terminator { term = rewriter.term(value); }
            blocks[id.id] = MirBlock { id, ops, terminator: term }; order.push(id);
        } }
        functions.push(MirFunction { name: func.name, symbol_id: func.symbol_id, args: func.args, locals, ret_type: func.ret_type,
            blocks, block_order: order, entry_block: func.entry_block, is_async: func.is_async, is_method: func.is_method });
    }
    let structs = Vec<MirStruct>.new(); for def in program.structs { let fields = Vec<MirField>.new(); for field in def.fields { fields.push(field); }
        structs.push(MirStruct { name: def.name, symbol_id: def.symbol_id, fields, type_id: def.type_id });
    }
    MirProgram { functions, structs, enums: program.enums, externs: program.externs }
}

pub struct MirLocalSet {
    let data: Dict<i32, Bool>;
    pub static def new() -> MirLocalSet { MirLocalSet { data: Dict<i32, Bool>.with_capacity(16, 0) } }
    pub def add(id: MirLocalId) -> Void { self.data[id.id] = true; }
    pub def remove(id: MirLocalId) -> Void { self.data.remove(id.id); }
    pub def contains(id: MirLocalId) -> Bool { self.data.contains(id.id) }
    pub def len() -> i32 { self.data.len() as i32 }
    pub def values() -> Vec<MirLocalId> {
        let out = Vec<MirLocalId>.new(); for entry in self.data.entries() { out.push(MirLocalId { id: entry.key }); }
        var i = 1; while i < out.len() { var j = i; while j > 0 && out[j].id < out[j-1].id {
            let old = out[j]; out[j] = out[j-1]; out[j-1] = old; j -= 1;
        } i += 1; } out
    }
    pub def copy() -> MirLocalSet { let out = MirLocalSet.new(); out.extend(self); out }
    pub def extend(other: MirLocalSet) -> Void { for id in other.values() { self.add(id); } }
    pub def difference(other: MirLocalSet) -> MirLocalSet { let out = MirLocalSet.new(); for id in self.values() { if !other.contains(id) { out.add(id); } } out }
    pub def equals(other: MirLocalSet) -> Bool { if self.len() != other.len() { return false; } for id in self.values() { if !other.contains(id) { return false; } } true }
}
pub def mir_operand_place(value: MirOperand) -> MirPlace? { switch value { case .copy(let p) | .move(let p): p; default: nil; } }
pub def mir_operand_local(value: MirOperand) -> MirLocalId? { if let p = mir_operand_place(value) { return p.base; } nil }
pub def mir_needs_arc(type_id: TypeId, types: TypeTable) -> Bool {
    if types.is_heap_type(type_id) || types.is_function(type_id) { return true; }
    if let inner = types.get_optional_inner(type_id) { return types.is_heap_type(inner) || types.is_function(inner); } false
}
pub def mir_references_local(op: MirOp, id: MirLocalId) -> Bool {
    for operand in mir_op_operands(op) { if let local = mir_operand_local(operand) { if local == id { return true; } } }
    for place in mir_op_places(op) { if place.base == id { return true; } } false
}
pub def mir_predecessors(func: MirFunction) -> Dict<i32, Vec<MirBlockId>> {
    let out = Dict<i32, Vec<MirBlockId>>.with_capacity(16, 0); for id in func.block_order { out[id.id] = Vec<MirBlockId>.new(); }
    for id in func.block_order { if let block = func.get_block(id) { if let term = block.terminator {
        for target in mir_targets(term) { if let list = out[target.id] { list.push(id); } }
    } } } out
}
pub struct MirBlockLiveness {
    pub let uses: MirLocalSet; pub let defs: MirLocalSet;
    pub var live_in: MirLocalSet; pub var live_out: MirLocalSet; pub var owned_at_entry: MirLocalSet;
}
pub def mir_liveness(func: MirFunction, tracked: MirLocalSet) -> Dict<i32, MirBlockLiveness> {
    let out = Dict<i32, MirBlockLiveness>.with_capacity(16, 0);
    for id in func.block_order { if let block = func.get_block(id) {
        let uses = MirLocalSet.new(); let defs = MirLocalSet.new();
        for op in block.ops {
            for operand in mir_op_operands(op) { if let local = mir_operand_local(operand) { if tracked.contains(local) && !defs.contains(local) { uses.add(local); } } }
            for place in mir_op_places(op) { var write = false;
                switch op { case .assign: write = place.projections.len() == 0; default: {} }
                if write { if tracked.contains(place.base) { defs.add(place.base); } }
                else if tracked.contains(place.base) && !defs.contains(place.base) { uses.add(place.base); }
            }
            if let result = mir_op_result(op) { if tracked.contains(result) { defs.add(result); } }
        }
        if let term = block.terminator { for operand in mir_term_operands(term) { if let local = mir_operand_local(operand) {
            if tracked.contains(local) && !defs.contains(local) { uses.add(local); }
        } } }
        out[id.id] = MirBlockLiveness { uses, defs, live_in: MirLocalSet.new(), live_out: MirLocalSet.new(), owned_at_entry: MirLocalSet.new() };
    } }
    var changed = true;
    while changed { changed = false; var index = func.block_order.len(); while index > 0 { index -= 1; let id = func.block_order[index];
        if let analysis = out[id.id] { let next_out = MirLocalSet.new(); if let block = func.get_block(id) { if let term = block.terminator {
            for target in mir_targets(term) { if let successor = out[target.id] { next_out.extend(successor.live_in); } }
        } }
        let next_in = next_out.difference(analysis.defs); next_in.extend(analysis.uses);
        if !next_in.equals(analysis.live_in) || !next_out.equals(analysis.live_out) { changed = true; analysis.live_in = next_in; analysis.live_out = next_out; }
    } } }
    let predecessors = mir_predecessors(func);
    for id in func.block_order { if let list = predecessors[id.id] { if list.len() == 1 {
        if let pred = out[list[0].id] { if let current = out[id.id] { current.owned_at_entry = pred.live_out.difference(current.live_in); } }
    } } } out
}
