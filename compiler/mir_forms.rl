// Checked-in Rolang definitions. Keep node fields, visitors and dumps in sync.
pub import "mir_ops.rl"
pub import "ids.rl"
// Integer constants and switch cases retain arbitrary-precision decimal text.
pub enum MirScalar { case integer(String); case floating(f64); case boolean(Bool); case text(String); case none; }
pub struct MirLocalId { pub let id: i32; pub def __eq__(other: MirLocalId) -> Bool { self.id == other.id } pub def __ne__(other: MirLocalId) -> Bool { self.id != other.id } }
pub struct MirBlockId { pub let id: i32; pub def __eq__(other: MirBlockId) -> Bool { self.id == other.id } pub def __ne__(other: MirBlockId) -> Bool { self.id != other.id } }
pub struct MirValueId { pub let id: i32; pub def __eq__(other: MirValueId) -> Bool { self.id == other.id } pub def __ne__(other: MirValueId) -> Bool { self.id != other.id } }
pub enum MirProjection { case field(String, TypeId); case index(MirOperand, TypeId); case deref(TypeId); }
pub struct MirPlace { pub let base: MirLocalId; pub let projections: Vec<MirProjection>; pub let type_id: TypeId; }
pub enum MirConstantKind { case int; case float; case bool_type; case string; case nil; case unit; }
pub struct MirConstant { pub let kind: MirConstantKind; pub let value: MirScalar; pub let type_id: TypeId; }
pub enum MirOperand { case copy(MirPlace); case move(MirPlace); case constant(MirConstant);
    pub def type_id() -> TypeId { switch self { case .copy(let p): p.type_id; case .move(let p): p.type_id; case .constant(let c): c.type_id; } }
}
pub struct MirBinOpData {
    pub var result: MirLocalId;
    pub var op: BinOpKind;
    pub var left: MirOperand;
    pub var right: MirOperand;
    pub var result_type: TypeId;
}
pub struct MirCmpOpData {
    pub var result: MirLocalId;
    pub var op: CmpOpKind;
    pub var left: MirOperand;
    pub var right: MirOperand;
}
pub struct MirUnaryOpData {
    pub var result: MirLocalId;
    pub var op: UnaryOpKind;
    pub var operand: MirOperand;
    pub var result_type: TypeId;
}
pub struct MirCastOpData {
    pub var result: MirLocalId;
    pub var operand: MirOperand;
    pub var target_type: TypeId;
}
pub struct MirMakeStructData {
    pub var result: MirLocalId;
    pub var struct_type: TypeId;
    pub var fields: Vec<(String, MirOperand)>;
}
pub struct MirMakeEnumData {
    pub var result: MirLocalId;
    pub var enum_type: TypeId;
    pub var case_name: String;
    pub var tag: i32;
    pub var payload: Vec<MirOperand>;
}
pub struct MirMakeSomeData {
    pub var result: MirLocalId;
    pub var value: MirOperand;
    pub var result_type: TypeId;
}
pub struct MirMakeNoneData {
    pub var result: MirLocalId;
    pub var result_type: TypeId;
}
pub struct MirExtractFieldData {
    pub var result: MirLocalId;
    pub var aggregate: MirOperand;
    pub var field_name: String;
    pub var field_index: i32;
    pub var result_type: TypeId;
}
pub struct MirExtractClosureCaptureData {
    pub var result: MirLocalId;
    pub var closure: MirOperand;
    pub var capture_index: i32;
    pub var result_type: TypeId;
}
pub struct MirExtractEnumPayloadData {
    pub var result: MirLocalId;
    pub var enum_val: MirOperand;
    pub var case_name: String;
    pub var payload_index: i32;
    pub var result_type: TypeId;
}
pub struct MirGetTagData {
    pub var result: MirLocalId;
    pub var enum_val: MirOperand;
}
pub struct MirAssignData {
    pub var place: MirPlace;
    pub var value: MirOperand;
}
pub struct MirStoreData {
    pub var place: MirPlace;
    pub var value: MirOperand;
}
pub struct MirLoadData {
    pub var result: MirLocalId;
    pub var place: MirPlace;
}
pub struct MirRetainData {
    pub var operand: MirOperand;
}
pub struct MirReleaseData {
    pub var operand: MirOperand;
}
pub struct MirAllocObjData {
    pub var result: MirLocalId;
    pub var type_id: i32;
    pub var payload_size: i64;
    pub var result_type: TypeId;
}
pub struct MirCloneData {
    pub var result: MirLocalId;
    pub var value: MirOperand;
    pub var result_type: TypeId;
}
pub struct MirCallStaticData {
    pub var result: MirLocalId?;
    pub var func_name: String;
    pub var func_symbol: SymbolId?;
    pub var args: Vec<MirOperand>;
    pub var result_type: TypeId;
}
pub struct MirCallVTableData {
    pub var result: MirLocalId?;
    pub var receiver: MirOperand;
    pub var method_name: String;
    pub var args: Vec<MirOperand>;
    pub var result_type: TypeId;
}
pub struct MirCallWitnessData {
    pub var result: MirLocalId?;
    pub var witness_type: TypeId;
    pub var method_name: String;
    pub var args: Vec<MirOperand>;
    pub var result_type: TypeId;
}
pub struct MirMakeClosureData {
    pub var result: MirLocalId;
    pub var func_name: String;
    pub var captures: Vec<MirOperand>;
    pub var result_type: TypeId;
}
pub struct MirCallClosureData {
    pub var result: MirLocalId?;
    pub var closure: MirOperand;
    pub var args: Vec<MirOperand>;
    pub var result_type: TypeId;
}
pub struct MirBoxExistentialData {
    pub var result: MirLocalId;
    pub var value: MirOperand;
    pub var concrete_type: TypeId;
    pub var protocol_type: TypeId;
    pub var result_type: TypeId;
}
pub struct MirExistentialCheckTypeData {
    pub var result: MirLocalId;
    pub var existential: MirOperand;
    pub var concrete_type: TypeId;
    pub var protocol_type: TypeId;
}
pub struct MirExistentialUnboxData {
    pub var result: MirLocalId;
    pub var existential: MirOperand;
    pub var concrete_type: TypeId;
    pub var protocol_type: TypeId;
    pub var result_type: TypeId;
}
pub struct MirSuspendData {
    pub var state_id: i32;
    pub var result: MirLocalId?;
    pub var result_type: TypeId;
}
pub struct MirTaskSpawnData {
    pub var result: MirLocalId;
    pub var async_func_name: String;
    pub var args: Vec<MirOperand>;
    pub var result_type: TypeId;
    pub var frame: MirOperand?;
}
pub struct MirTaskJoinData {
    pub var result: MirLocalId?;
    pub var task_handle: MirOperand;
    pub var result_type: TypeId;
}
pub struct MirTaskCompleteData {
    pub var task_handle: MirOperand;
    pub var result: MirOperand?;
}
pub struct MirAllocAsyncFrameData {
    pub var result: MirLocalId;
    pub var frame_type: TypeId;
}
pub struct MirSchedulerRunData {
    pub var until_handle: MirOperand?;
    pub var destroy_after: Bool;
}
pub struct MirTaskGetResultData {
    pub var result: MirLocalId;
    pub var task_handle: MirOperand;
    pub var result_type: TypeId;
    pub var consume: Bool;
}

pub enum MirOp {
    case bin_op(MirBinOpData);
    case cmp_op(MirCmpOpData);
    case unary_op(MirUnaryOpData);
    case cast_op(MirCastOpData);
    case make_struct(MirMakeStructData);
    case make_enum(MirMakeEnumData);
    case make_some(MirMakeSomeData);
    case make_none(MirMakeNoneData);
    case extract_field(MirExtractFieldData);
    case extract_closure_capture(MirExtractClosureCaptureData);
    case extract_enum_payload(MirExtractEnumPayloadData);
    case get_tag(MirGetTagData);
    case assign(MirAssignData);
    case store(MirStoreData);
    case load(MirLoadData);
    case retain(MirRetainData);
    case release(MirReleaseData);
    case alloc_obj(MirAllocObjData);
    case clone(MirCloneData);
    case gc_check;
    case call_static(MirCallStaticData);
    case call_v_table(MirCallVTableData);
    case call_witness(MirCallWitnessData);
    case make_closure(MirMakeClosureData);
    case call_closure(MirCallClosureData);
    case box_existential(MirBoxExistentialData);
    case existential_check_type(MirExistentialCheckTypeData);
    case existential_unbox(MirExistentialUnboxData);
    case suspend(MirSuspendData);
    case task_spawn(MirTaskSpawnData);
    case task_join(MirTaskJoinData);
    case task_yield;
    case task_complete(MirTaskCompleteData);
    case alloc_async_frame(MirAllocAsyncFrameData);
    case scheduler_run(MirSchedulerRunData);
    case task_get_result(MirTaskGetResultData);
    pub def kind() -> String {
        switch self {
            case .bin_op(_): "BinOp";
            case .cmp_op(_): "CmpOp";
            case .unary_op(_): "UnaryOp";
            case .cast_op(_): "CastOp";
            case .make_struct(_): "MakeStruct";
            case .make_enum(_): "MakeEnum";
            case .make_some(_): "MakeSome";
            case .make_none(_): "MakeNone";
            case .extract_field(_): "ExtractField";
            case .extract_closure_capture(_): "ExtractClosureCapture";
            case .extract_enum_payload(_): "ExtractEnumPayload";
            case .get_tag(_): "GetTag";
            case .assign(_): "Assign";
            case .store(_): "Store";
            case .load(_): "Load";
            case .retain(_): "Retain";
            case .release(_): "Release";
            case .alloc_obj(_): "AllocObj";
            case .clone(_): "Clone";
            case .gc_check: "GCCheck";
            case .call_static(_): "CallStatic";
            case .call_v_table(_): "CallVTable";
            case .call_witness(_): "CallWitness";
            case .make_closure(_): "MakeClosure";
            case .call_closure(_): "CallClosure";
            case .box_existential(_): "BoxExistential";
            case .existential_check_type(_): "ExistentialCheckType";
            case .existential_unbox(_): "ExistentialUnbox";
            case .suspend(_): "Suspend";
            case .task_spawn(_): "TaskSpawn";
            case .task_join(_): "TaskJoin";
            case .task_yield: "TaskYield";
            case .task_complete(_): "TaskComplete";
            case .alloc_async_frame(_): "AllocAsyncFrame";
            case .scheduler_run(_): "SchedulerRun";
            case .task_get_result(_): "TaskGetResult";
        }
    }
}
pub struct MirBranchData {
    pub var target: MirBlockId;
}
pub struct MirCondBranchData {
    pub var condition: MirOperand;
    pub var true_target: MirBlockId;
    pub var false_target: MirBlockId;
}
pub struct MirSwitchIntData {
    pub var value: MirOperand;
    pub var cases: Vec<(String, MirBlockId)>;
    pub var default: MirBlockId;
}
pub struct MirReturnData {
    pub var value: MirOperand?;
}

pub enum MirTerm {
    case branch(MirBranchData);
    case cond_branch(MirCondBranchData);
    case switch_int(MirSwitchIntData);
    case return_stmt(MirReturnData);
    case unreachable;
    pub def kind() -> String {
        switch self {
            case .branch(_): "Branch";
            case .cond_branch(_): "CondBranch";
            case .switch_int(_): "SwitchInt";
            case .return_stmt(_): "Return";
            case .unreachable: "Unreachable";
        }
    }
}
