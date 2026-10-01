pub import "mir_analysis.rl"

pub struct MirOwnership {
    pub var produces: MirLocalId?;
    pub let consumes: MirLocalSet;
    pub let copies: Vec<MirPlace>;
    pub let post_retains: Vec<MirPlace>;
    pub let pre_releases: Vec<MirPlace>;
    def take(value: MirOperand, refs: MirLocalSet, types: TypeTable) -> Void {
        switch value {
            case .copy(let place): if mir_needs_arc(place.type_id, types) { self.copies.push(place); }
            case .move(let place): if place.projections.len() == 0 && refs.contains(place.base) { self.consumes.add(place.base); }
            default: {}
        }
    }
}
pub def mir_ref_locals(func: MirFunction, types: TypeTable) -> MirLocalSet {
    let refs = MirLocalSet.new(); for local in func.locals { if mir_needs_arc(local.type_id, types) { refs.add(local.id); } } refs
}
pub def mir_local_type(func: MirFunction, id: MirLocalId) -> TypeId {
    for local in func.locals { if local.id == id { return local.type_id; } } func.ret_type
}
pub def mir_ownership(op: MirOp, refs: MirLocalSet, types: TypeTable) -> MirOwnership {
    let out = MirOwnership { produces: nil, consumes: MirLocalSet.new(), copies: Vec<MirPlace>.new(),
        post_retains: Vec<MirPlace>.new(), pre_releases: Vec<MirPlace>.new() };
    var owned = false; var borrowed = false;
    switch op {
        case .call_static, .call_v_table, .call_closure, .call_witness,
             .alloc_obj, .clone, .alloc_async_frame, .task_get_result, .make_none: owned = true;
        case .extract_field, .extract_closure_capture, .extract_enum_payload, .load, .existential_unbox: borrowed = true;
        case .cast_op(let d): if refs.contains(d.result) { owned = true; out.take(d.operand, refs, types); }
        case .make_struct(let d): owned = true; for field in d.fields { out.take(field.1, refs, types); }
        case .make_enum(let d): owned = true; for value in d.payload { out.take(value, refs, types); }
        case .make_some(let d): owned = true; out.take(d.value, refs, types);
        case .make_closure(let d): owned = true; for value in d.captures { out.take(value, refs, types); }
        case .box_existential(let d): owned = true; out.take(d.value, refs, types);
        case .assign(let d):
            if mir_needs_arc(d.place.type_id, types) { out.take(d.value, refs, types); if d.place.projections.len() > 0 { out.pre_releases.push(d.place); } }
            if d.place.projections.len() == 0 && refs.contains(d.place.base) { out.produces = d.place.base; }
        case .store(let d): if mir_needs_arc(d.place.type_id, types) { out.take(d.value, refs, types); out.pre_releases.push(d.place); }
        case .task_spawn(let d): if let frame = d.frame { if let p = mir_operand_place(frame) {
            if p.projections.len() == 0 && refs.contains(p.base) { out.consumes.add(p.base); }
        } }
        default: {}
    }
    if owned || borrowed { if let result = mir_op_result(op) { if refs.contains(result) {
        out.produces = result;
        if borrowed { var type_id = types.error_type;
            switch op {
                case .extract_field(let d): type_id = d.result_type;
                case .extract_closure_capture(let d): type_id = d.result_type;
                case .extract_enum_payload(let d): type_id = d.result_type;
                case .existential_unbox(let d): type_id = d.result_type;
                case .load(let d): type_id = d.place.type_id;
                default: {}
            }
            out.post_retains.push(MirPlace { base: result, projections: Vec<MirProjection>.new(), type_id });
        }
    } } } out
}
def mir_release_local(func: MirFunction, id: MirLocalId) -> MirOp { MirOp.release(MirReleaseData { operand: mir_copy(id, mir_local_type(func, id)) }) }
def mir_return_local(block: MirBlock) -> MirLocalId? {
    if let term = block.terminator { switch term { case .return_stmt(let d): if let value = d.value { return mir_operand_local(value); } default: {} } } nil
}
pub def insert_arc_function(func: MirFunction, types: TypeTable) -> Void {
    let refs = mir_ref_locals(func, types); if refs.len() == 0 { return; }
    let liveness = mir_liveness(func, refs); let predecessors = mir_predecessors(func);
    let successors = Dict<i32, i32>.with_capacity(16, 0);
    let params = MirLocalSet.new(); for arg in func.args { params.add(arg.id); }
    var return_local: MirLocalId? = nil;
    for id in func.block_order { if let block = func.get_block(id) {
        if let term = block.terminator { successors[id.id] = mir_targets(term).len(); }
        if let existing = return_local {} else { return_local = mir_return_local(block); }
    } }
    for id in func.block_order { guard let block = func.get_block(id) else { continue; }
        guard let live = liveness[id.id] else { continue; }
        let out = Vec<MirOp>.new(); let owned = live.live_in.copy(); let consumed = MirLocalSet.new();
        for local in live.owned_at_entry.values() {
            var skip = params.contains(local); if let ret = return_local { if ret == local { skip = true; } }
            if !skip { out.push(mir_release_local(func, local)); }
        }
        for op in block.ops {
            switch op { case .retain, .release: out.push(op); continue; default: {} }
            let ownership = mir_ownership(op, refs, types);
            for place in ownership.copies { out.push(MirOp.retain(MirRetainData { operand: MirOperand.copy(place) })); }
            for place in ownership.pre_releases { out.push(MirOp.release(MirReleaseData { operand: MirOperand.copy(place) })); }
            switch op { case .assign(let d): if d.place.projections.len() == 0 && owned.contains(d.place.base) && !params.contains(d.place.base) && mir_needs_arc(d.place.type_id, types) {
                out.push(MirOp.release(MirReleaseData { operand: MirOperand.copy(d.place) })); owned.remove(d.place.base);
            } default: {} }
            out.push(op);
            for place in ownership.post_retains { out.push(MirOp.retain(MirRetainData { operand: MirOperand.copy(place) })); }
            if let result = ownership.produces { owned.add(result); consumed.remove(result); }
            for local in ownership.consumes.values() { owned.remove(local); consumed.add(local); }
        }
        let returned = mir_return_local(block);
        if let local = returned { if params.contains(local) && refs.contains(local) {
            out.push(MirOp.retain(MirRetainData { operand: mir_copy(local, mir_local_type(func, local)) }));
        } }
        let candidates = live.defs.copy(); candidates.extend(live.live_in);
        for local in candidates.values() {
            var skip = live.live_out.contains(local) || consumed.contains(local) || params.contains(local);
            if let ret = returned { if ret == local { skip = true; } }
            if !skip { out.push(mir_release_local(func, local)); }
        }
        block.ops = out;
    }
    // Split a fork-to-merge edge when it carries an owner dead at the merge.
    // Releasing in the merge would destroy values on already-cleaned paths.
    var next_id = 0; for id in func.block_order { if id.id >= next_id { next_id = id.id+1; } }
    let original_order = Vec<MirBlockId>.new(); for id in func.block_order { original_order.push(id); }
    for merge in original_order { if let preds = predecessors[merge.id] { if preds.len() > 1 {
        if let live = liveness[merge.id] { for pred in preds { if (successors[pred.id] ?? 0) > 1 {
            if let pred_live = liveness[pred.id] { let leaked = pred_live.live_out.difference(live.live_in); let releases = Vec<MirOp>.new();
                for local in leaked.values() { var skip = params.contains(local); if let ret = return_local { if local == ret { skip = true; } }
                    if !skip { releases.push(mir_release_local(func, local)); }
                }
                if releases.len() > 0 { let split = MirBlockId { id: next_id }; next_id += 1;
                    func.blocks[split.id] = MirBlock { id: split, ops: releases, terminator: MirTerm.branch(MirBranchData { target: merge }) };
                    func.block_order.push(split);
                    if let block = func.get_block(pred) { if let term = block.terminator {
                        let rewriter = MirRewriter.new(); rewriter.blocks[merge.id] = split; block.terminator = rewriter.term(term);
                    } }
                }
            }
        } } }
    } } }
}
pub def verify_arc_function(func: MirFunction, types: TypeTable) -> Vec<String> {
    let errors = Vec<String>.new(); let refs = mir_ref_locals(func, types);
    for id in func.block_order { if let block = func.get_block(id) {
        let retains = Dict<i32, i32>.with_capacity(16, 0); let releases = Dict<i32, i32>.with_capacity(16, 0);
        for op in block.ops { switch op {
            case .retain(let d): if let p = mir_operand_place(d.operand) { if p.projections.len() == 0 && refs.contains(p.base) { retains[p.base.id] = (retains[p.base.id] ?? 0)+1; } }
            case .release(let d): if let p = mir_operand_place(d.operand) { if p.projections.len() == 0 && refs.contains(p.base) {
                let count = (releases[p.base.id] ?? 0)+1; releases[p.base.id] = count;
                if count > (retains[p.base.id] ?? 0)+1 { errors.push(f"Function '{func.name}', block {id.id}: potential double-release of local {p.base.id}"); }
            } }
            default: let ownership = mir_ownership(op, refs, types); if let result = ownership.produces { retains[result.id] = (retains[result.id] ?? 0)+1; }
        } }
    } } errors
}
pub def insert_arc(program: MirProgram, types: TypeTable) -> Vec<String> {
    let errors = Vec<String>.new(); for func in program.functions { insert_arc_function(func, types); for error in verify_arc_function(func, types) { errors.push(error); } } errors
}
