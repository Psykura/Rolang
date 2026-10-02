// Checked-in Rolang definitions. Keep node fields, visitors and dumps in sync.
pub import "mir.rl"
pub def mir_op_operands(value: MirOp) -> Vec<MirOperand> {
let out = Vec<MirOperand>.new(); switch value {
case .bin_op(let data):
out.push(data.left);
out.push(data.right);
case .cmp_op(let data):
out.push(data.left);
out.push(data.right);
case .unary_op(let data):
out.push(data.operand);
case .cast_op(let data):
out.push(data.operand);
case .make_struct(let data):
for pair in data.fields { out.push(pair.1); }
case .make_enum(let data):
for value in data.payload { out.push(value); }
case .make_some(let data):
out.push(data.value);
case .extract_field(let data):
out.push(data.aggregate);
case .extract_closure_capture(let data):
out.push(data.closure);
case .extract_enum_payload(let data):
out.push(data.enum_val);
case .get_tag(let data):
out.push(data.enum_val);
case .assign(let data):
out.push(data.value);
case .store(let data):
out.push(data.value);
case .retain(let data):
out.push(data.operand);
case .release(let data):
out.push(data.operand);
case .clone(let data):
out.push(data.value);
case .call_static(let data):
for value in data.args { out.push(value); }
case .call_v_table(let data):
out.push(data.receiver);
for value in data.args { out.push(value); }
case .call_witness(let data):
for value in data.args { out.push(value); }
case .make_closure(let data):
for value in data.captures { out.push(value); }
case .call_closure(let data):
out.push(data.closure);
for value in data.args { out.push(value); }
case .box_existential(let data):
out.push(data.value);
case .existential_check_type(let data):
out.push(data.existential);
case .existential_unbox(let data):
out.push(data.existential);
case .task_spawn(let data):
for value in data.args { out.push(value); }
if let value = data.frame { out.push(value); }
case .task_join(let data):
out.push(data.task_handle);
case .task_complete(let data):
out.push(data.task_handle);
if let value = data.result { out.push(value); }
case .scheduler_run(let data):
if let value = data.until_handle { out.push(value); }
case .task_get_result(let data):
out.push(data.task_handle);
default: {}
} out
}
pub def mir_term_operands(value: MirTerm) -> Vec<MirOperand> {
let out = Vec<MirOperand>.new(); switch value {
case .cond_branch(let data):
out.push(data.condition);
case .switch_int(let data):
out.push(data.value);
case .return_stmt(let data):
if let value = data.value { out.push(value); }
default: {}
} out
}
pub def mir_op_result(value: MirOp) -> MirLocalId? { switch value {
case .bin_op(let data): return data.result;
case .cmp_op(let data): return data.result;
case .unary_op(let data): return data.result;
case .cast_op(let data): return data.result;
case .make_struct(let data): return data.result;
case .make_enum(let data): return data.result;
case .make_some(let data): return data.result;
case .make_none(let data): return data.result;
case .extract_field(let data): return data.result;
case .extract_closure_capture(let data): return data.result;
case .extract_enum_payload(let data): return data.result;
case .get_tag(let data): return data.result;
case .load(let data): return data.result;
case .alloc_obj(let data): return data.result;
case .clone(let data): return data.result;
case .call_static(let data): return data.result;
case .call_v_table(let data): return data.result;
case .call_witness(let data): return data.result;
case .make_closure(let data): return data.result;
case .call_closure(let data): return data.result;
case .box_existential(let data): return data.result;
case .existential_check_type(let data): return data.result;
case .existential_unbox(let data): return data.result;
case .suspend(let data): return data.result;
case .task_spawn(let data): return data.result;
case .task_join(let data): return data.result;
case .alloc_async_frame(let data): return data.result;
case .task_get_result(let data): return data.result;
default: return nil;
} }
pub def mir_op_places(value: MirOp) -> Vec<MirPlace> { let out = Vec<MirPlace>.new(); switch value {
case .assign(let data):
out.push(data.place);
case .store(let data):
out.push(data.place);
case .load(let data):
out.push(data.place);
default: {}
} out }
pub struct MirRewriter {
pub let locals: Dict<i32, MirLocalId>;
pub let blocks: Dict<i32, MirBlockId>;
pub let substitutions: Dict<i32, MirOperand>;
pub let fields: Dict<String, MirPlace>;
pub static def new() -> MirRewriter { MirRewriter { locals: Dict<i32, MirLocalId>.with_capacity(16, 0), blocks: Dict<i32, MirBlockId>.with_capacity(16, 0), substitutions: Dict<i32, MirOperand>.with_capacity(16, 0), fields: Dict<String, MirPlace>.with_capacity(16, 1) } }
pub def local(value: MirLocalId) -> MirLocalId { self.locals[value.id] ?? value }
pub def block(value: MirBlockId) -> MirBlockId { self.blocks[value.id] ?? value }
pub def place(value: MirPlace) -> MirPlace { if value.projections.len() == 1 { switch value.projections[0] { case .field(let name, _): if let replacement = self.fields[f"{value.base.id}:{name}"] { return replacement; } default: {} } } let projections = Vec<MirProjection>.new(); for p in value.projections { switch p { case .index(let operand, let type_id): projections.push(MirProjection.index(self.operand(operand), type_id)); default: projections.push(p); } } MirPlace { base: self.local(value.base), projections, type_id: value.type_id } }
pub def operand(value: MirOperand) -> MirOperand { switch value {
case .copy(let place): if place.projections.len() == 0 { if let replacement = self.substitutions[place.base.id] { return replacement; } } return MirOperand.copy(self.place(place));
case .move(let place): if place.projections.len() == 0 { if let replacement = self.substitutions[place.base.id] { return replacement; } } return MirOperand.move(self.place(place));
case .constant: return value;
} }
pub def op(value: MirOp) -> MirOp { switch value {
case .bin_op(let data):
return MirOp.bin_op(MirBinOpData { result: self.local(data.result), op: data.op, left: self.operand(data.left), right: self.operand(data.right), result_type: data.result_type });
case .cmp_op(let data):
return MirOp.cmp_op(MirCmpOpData { result: self.local(data.result), op: data.op, left: self.operand(data.left), right: self.operand(data.right) });
case .unary_op(let data):
return MirOp.unary_op(MirUnaryOpData { result: self.local(data.result), op: data.op, operand: self.operand(data.operand), result_type: data.result_type });
case .cast_op(let data):
return MirOp.cast_op(MirCastOpData { result: self.local(data.result), operand: self.operand(data.operand), target_type: data.target_type });
case .make_struct(let data):
let fields = Vec<(String, MirOperand)>.new(); for x in data.fields { fields.push((x.0, self.operand(x.1))); }
return MirOp.make_struct(MirMakeStructData { result: self.local(data.result), struct_type: data.struct_type, fields: fields });
case .make_enum(let data):
let payload = Vec<MirOperand>.new(); for x in data.payload { payload.push(self.operand(x)); }
return MirOp.make_enum(MirMakeEnumData { result: self.local(data.result), enum_type: data.enum_type, case_name: data.case_name, tag: data.tag, payload: payload });
case .make_some(let data):
return MirOp.make_some(MirMakeSomeData { result: self.local(data.result), value: self.operand(data.value), result_type: data.result_type });
case .make_none(let data):
return MirOp.make_none(MirMakeNoneData { result: self.local(data.result), result_type: data.result_type });
case .extract_field(let data):
return MirOp.extract_field(MirExtractFieldData { result: self.local(data.result), aggregate: self.operand(data.aggregate), field_name: data.field_name, field_index: data.field_index, result_type: data.result_type });
case .extract_closure_capture(let data):
return MirOp.extract_closure_capture(MirExtractClosureCaptureData { result: self.local(data.result), closure: self.operand(data.closure), capture_index: data.capture_index, result_type: data.result_type });
case .extract_enum_payload(let data):
return MirOp.extract_enum_payload(MirExtractEnumPayloadData { result: self.local(data.result), enum_val: self.operand(data.enum_val), case_name: data.case_name, payload_index: data.payload_index, result_type: data.result_type });
case .get_tag(let data):
return MirOp.get_tag(MirGetTagData { result: self.local(data.result), enum_val: self.operand(data.enum_val) });
case .assign(let data):
return MirOp.assign(MirAssignData { place: self.place(data.place), value: self.operand(data.value) });
case .store(let data):
return MirOp.store(MirStoreData { place: self.place(data.place), value: self.operand(data.value) });
case .load(let data):
return MirOp.load(MirLoadData { result: self.local(data.result), place: self.place(data.place) });
case .retain(let data):
return MirOp.retain(MirRetainData { operand: self.operand(data.operand) });
case .release(let data):
return MirOp.release(MirReleaseData { operand: self.operand(data.operand) });
case .alloc_obj(let data):
return MirOp.alloc_obj(MirAllocObjData { result: self.local(data.result), type_id: data.type_id, payload_size: data.payload_size, result_type: data.result_type });
case .clone(let data):
return MirOp.clone(MirCloneData { result: self.local(data.result), value: self.operand(data.value), result_type: data.result_type });
case .gc_check: return MirOp.gc_check();
case .call_static(let data):
var result: MirLocalId? = nil; if let x = data.result { result = self.local(x); }
let args = Vec<MirOperand>.new(); for x in data.args { args.push(self.operand(x)); }
return MirOp.call_static(MirCallStaticData { result: result, func_name: data.func_name, func_symbol: data.func_symbol, args: args, result_type: data.result_type });
case .call_v_table(let data):
var result: MirLocalId? = nil; if let x = data.result { result = self.local(x); }
let args = Vec<MirOperand>.new(); for x in data.args { args.push(self.operand(x)); }
return MirOp.call_v_table(MirCallVTableData { result: result, receiver: self.operand(data.receiver), method_name: data.method_name, args: args, result_type: data.result_type });
case .call_witness(let data):
var result: MirLocalId? = nil; if let x = data.result { result = self.local(x); }
let args = Vec<MirOperand>.new(); for x in data.args { args.push(self.operand(x)); }
return MirOp.call_witness(MirCallWitnessData { result: result, witness_type: data.witness_type, method_name: data.method_name, args: args, result_type: data.result_type });
case .make_closure(let data):
let captures = Vec<MirOperand>.new(); for x in data.captures { captures.push(self.operand(x)); }
return MirOp.make_closure(MirMakeClosureData { result: self.local(data.result), func_name: data.func_name, captures: captures, result_type: data.result_type });
case .call_closure(let data):
var result: MirLocalId? = nil; if let x = data.result { result = self.local(x); }
let args = Vec<MirOperand>.new(); for x in data.args { args.push(self.operand(x)); }
return MirOp.call_closure(MirCallClosureData { result: result, closure: self.operand(data.closure), args: args, result_type: data.result_type });
case .box_existential(let data):
return MirOp.box_existential(MirBoxExistentialData { result: self.local(data.result), value: self.operand(data.value), concrete_type: data.concrete_type, protocol_type: data.protocol_type, result_type: data.result_type });
case .existential_check_type(let data):
return MirOp.existential_check_type(MirExistentialCheckTypeData { result: self.local(data.result), existential: self.operand(data.existential), concrete_type: data.concrete_type, protocol_type: data.protocol_type });
case .existential_unbox(let data):
return MirOp.existential_unbox(MirExistentialUnboxData { result: self.local(data.result), existential: self.operand(data.existential), concrete_type: data.concrete_type, protocol_type: data.protocol_type, result_type: data.result_type });
case .suspend(let data):
var result: MirLocalId? = nil; if let x = data.result { result = self.local(x); }
return MirOp.suspend(MirSuspendData { state_id: data.state_id, result: result, result_type: data.result_type });
case .task_spawn(let data):
let args = Vec<MirOperand>.new(); for x in data.args { args.push(self.operand(x)); }
var frame: MirOperand? = nil; if let x = data.frame { frame = self.operand(x); }
return MirOp.task_spawn(MirTaskSpawnData { result: self.local(data.result), async_func_name: data.async_func_name, args: args, result_type: data.result_type, frame: frame });
case .task_join(let data):
var result: MirLocalId? = nil; if let x = data.result { result = self.local(x); }
return MirOp.task_join(MirTaskJoinData { result: result, task_handle: self.operand(data.task_handle), result_type: data.result_type });
case .task_yield: return MirOp.task_yield();
case .task_complete(let data):
var result: MirOperand? = nil; if let x = data.result { result = self.operand(x); }
return MirOp.task_complete(MirTaskCompleteData { task_handle: self.operand(data.task_handle), result: result });
case .alloc_async_frame(let data):
return MirOp.alloc_async_frame(MirAllocAsyncFrameData { result: self.local(data.result), frame_type: data.frame_type });
case .scheduler_run(let data):
var until_handle: MirOperand? = nil; if let x = data.until_handle { until_handle = self.operand(x); }
return MirOp.scheduler_run(MirSchedulerRunData { until_handle: until_handle, destroy_after: data.destroy_after });
case .task_get_result(let data):
return MirOp.task_get_result(MirTaskGetResultData { result: self.local(data.result), task_handle: self.operand(data.task_handle), result_type: data.result_type, consume: data.consume });
case .debug_location(let data):
return MirOp.debug_location(data);
} }
pub def term(value: MirTerm) -> MirTerm { switch value {
case .branch(let data):
return MirTerm.branch(MirBranchData { target: self.block(data.target) });
case .cond_branch(let data):
return MirTerm.cond_branch(MirCondBranchData { condition: self.operand(data.condition), true_target: self.block(data.true_target), false_target: self.block(data.false_target) });
case .switch_int(let data):
let cases = Vec<(String, MirBlockId)>.new(); for x in data.cases { cases.push((x.0, self.block(x.1))); }
return MirTerm.switch_int(MirSwitchIntData { value: self.operand(data.value), cases: cases, default: self.block(data.default) });
case .return_stmt(let data):
var value: MirOperand? = nil; if let x = data.value { value = self.operand(x); }
return MirTerm.return_stmt(MirReturnData { value: value });
case .unreachable: return MirTerm.unreachable();
} }
}
