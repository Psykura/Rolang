// Checked-in Rolang definitions. Keep node fields, visitors and dumps in sync.
pub import "mir.rl"
import std.io
import std.string_builder
def mir_hex(value: String) -> String {
    let digits = "0123456789abcdef"; var out = ""; var i = 0;
    while i < (value.len() as i32) { let byte = value.byte_at(i); out += digits.substring(byte/16, 1)+digits.substring(byte%16, 1); i += 1; } out
}
def mir_type_text(type_id: TypeId, types: TypeTable) -> String { "T:"+mir_hex(types.format_type(type_id)) }
def mir_bool_text(value: Bool) -> String { if value { return "B:1"; } "B:0" }
def mir_scalar_text(value: MirScalar) -> String { switch value {
    case .integer(let x): "I:"+x; case .floating(let x): "F:"+x.to_string();
    case .text(let x): "X:"+mir_hex(x); case .boolean(let x): mir_bool_text(x); case .none: "nil";
} }
def mir_place_text(place: MirPlace, types: TypeTable) -> String {
    var out = "L:"+place.base.id.to_string()+","+mir_type_text(place.type_id, types)+"[";
    for projection in place.projections { switch projection {
        case .field(let name, let type_id): out += "field(X:"+mir_hex(name)+","+mir_type_text(type_id, types)+")";
        case .index(let index, let type_id): out += "index("+mir_operand_text(index, types)+","+mir_type_text(type_id, types)+")";
        case .deref(let type_id): out += "deref("+mir_type_text(type_id, types)+")";
    } } out+"]"
}
def mir_operand_text(value: MirOperand, types: TypeTable) -> String { switch value {
    case .copy(let place): return "copy("+mir_place_text(place, types)+")";
    case .move(let place): return "move("+mir_place_text(place, types)+")";
    case .constant(let constant): var kind = ""; switch constant.kind {
        case .int: kind = "INT"; case .float: kind = "FLOAT"; case .bool_type: kind = "BOOL";
        case .string: kind = "STRING"; case .nil: kind = "NIL"; case .unit: kind = "UNIT";
    } return "constant("+kind+","+mir_scalar_text(constant.value)+","+mir_type_text(constant.type_id, types)+")";
} }

pub def mir_format_op(value: MirOp, types: TypeTable, sink: StringBuilder) -> Void {
sink.append_line("NODE|"+value.kind()); switch value {
case .bin_op(let data):
sink.append_line("result|"+"L:"+data.result.id.to_string());
sink.append_line("op|"+"E:"+data.op.name());
sink.append_line("left|"+mir_operand_text(data.left, types));
sink.append_line("right|"+mir_operand_text(data.right, types));
sink.append_line("result_type|"+mir_type_text(data.result_type, types));
case .cmp_op(let data):
sink.append_line("result|"+"L:"+data.result.id.to_string());
sink.append_line("op|"+"E:"+data.op.name());
sink.append_line("left|"+mir_operand_text(data.left, types));
sink.append_line("right|"+mir_operand_text(data.right, types));
case .unary_op(let data):
sink.append_line("result|"+"L:"+data.result.id.to_string());
sink.append_line("op|"+"E:"+data.op.name());
sink.append_line("operand|"+mir_operand_text(data.operand, types));
sink.append_line("result_type|"+mir_type_text(data.result_type, types));
case .cast_op(let data):
sink.append_line("result|"+"L:"+data.result.id.to_string());
sink.append_line("operand|"+mir_operand_text(data.operand, types));
sink.append_line("target_type|"+mir_type_text(data.target_type, types));
case .make_struct(let data):
sink.append_line("result|"+"L:"+data.result.id.to_string());
sink.append_line("struct_type|"+mir_type_text(data.struct_type, types));
sink.append_line("fields|"+"len:"+data.fields.len().to_string());
for pair in data.fields { sink.append_line("elem|("+"X:"+mir_hex(pair.0)+","+mir_operand_text(pair.1, types)+")"); }
case .make_enum(let data):
sink.append_line("result|"+"L:"+data.result.id.to_string());
sink.append_line("enum_type|"+mir_type_text(data.enum_type, types));
sink.append_line("case_name|"+"X:"+mir_hex(data.case_name));
sink.append_line("tag|"+"I:"+data.tag.to_string());
sink.append_line("payload|"+"len:"+data.payload.len().to_string());
for x in data.payload { sink.append_line("elem|"+mir_operand_text(x, types)); }
case .make_some(let data):
sink.append_line("result|"+"L:"+data.result.id.to_string());
sink.append_line("value|"+mir_operand_text(data.value, types));
sink.append_line("result_type|"+mir_type_text(data.result_type, types));
case .make_none(let data):
sink.append_line("result|"+"L:"+data.result.id.to_string());
sink.append_line("result_type|"+mir_type_text(data.result_type, types));
case .extract_field(let data):
sink.append_line("result|"+"L:"+data.result.id.to_string());
sink.append_line("aggregate|"+mir_operand_text(data.aggregate, types));
sink.append_line("field_name|"+"X:"+mir_hex(data.field_name));
sink.append_line("field_index|"+"I:"+data.field_index.to_string());
sink.append_line("result_type|"+mir_type_text(data.result_type, types));
case .extract_closure_capture(let data):
sink.append_line("result|"+"L:"+data.result.id.to_string());
sink.append_line("closure|"+mir_operand_text(data.closure, types));
sink.append_line("capture_index|"+"I:"+data.capture_index.to_string());
sink.append_line("result_type|"+mir_type_text(data.result_type, types));
case .extract_enum_payload(let data):
sink.append_line("result|"+"L:"+data.result.id.to_string());
sink.append_line("enum_val|"+mir_operand_text(data.enum_val, types));
sink.append_line("case_name|"+"X:"+mir_hex(data.case_name));
sink.append_line("payload_index|"+"I:"+data.payload_index.to_string());
sink.append_line("result_type|"+mir_type_text(data.result_type, types));
case .get_tag(let data):
sink.append_line("result|"+"L:"+data.result.id.to_string());
sink.append_line("enum_val|"+mir_operand_text(data.enum_val, types));
case .assign(let data):
sink.append_line("place|"+mir_place_text(data.place, types));
sink.append_line("value|"+mir_operand_text(data.value, types));
case .store(let data):
sink.append_line("place|"+mir_place_text(data.place, types));
sink.append_line("value|"+mir_operand_text(data.value, types));
case .load(let data):
sink.append_line("result|"+"L:"+data.result.id.to_string());
sink.append_line("place|"+mir_place_text(data.place, types));
case .retain(let data):
sink.append_line("operand|"+mir_operand_text(data.operand, types));
case .release(let data):
sink.append_line("operand|"+mir_operand_text(data.operand, types));
case .alloc_obj(let data):
sink.append_line("result|"+"L:"+data.result.id.to_string());
sink.append_line("type_id|"+"I:"+data.type_id.to_string());
sink.append_line("payload_size|"+"I:"+data.payload_size.to_string());
sink.append_line("result_type|"+mir_type_text(data.result_type, types));
case .clone(let data):
sink.append_line("result|"+"L:"+data.result.id.to_string());
sink.append_line("value|"+mir_operand_text(data.value, types));
sink.append_line("result_type|"+mir_type_text(data.result_type, types));
case .call_static(let data):
if let x = data.result { sink.append_line("result|"+"L:"+x.id.to_string()); } else { sink.append_line("result|"+"nil"); }
sink.append_line("func_name|"+"X:"+mir_hex(data.func_name));
if let x = data.func_symbol { sink.append_line("func_symbol|"+"S:"+x.id.to_string()); } else { sink.append_line("func_symbol|"+"nil"); }
sink.append_line("args|"+"len:"+data.args.len().to_string());
for x in data.args { sink.append_line("elem|"+mir_operand_text(x, types)); }
sink.append_line("result_type|"+mir_type_text(data.result_type, types));
case .call_v_table(let data):
if let x = data.result { sink.append_line("result|"+"L:"+x.id.to_string()); } else { sink.append_line("result|"+"nil"); }
sink.append_line("receiver|"+mir_operand_text(data.receiver, types));
sink.append_line("method_name|"+"X:"+mir_hex(data.method_name));
sink.append_line("args|"+"len:"+data.args.len().to_string());
for x in data.args { sink.append_line("elem|"+mir_operand_text(x, types)); }
sink.append_line("result_type|"+mir_type_text(data.result_type, types));
case .call_witness(let data):
if let x = data.result { sink.append_line("result|"+"L:"+x.id.to_string()); } else { sink.append_line("result|"+"nil"); }
sink.append_line("witness_type|"+mir_type_text(data.witness_type, types));
sink.append_line("method_name|"+"X:"+mir_hex(data.method_name));
sink.append_line("args|"+"len:"+data.args.len().to_string());
for x in data.args { sink.append_line("elem|"+mir_operand_text(x, types)); }
sink.append_line("result_type|"+mir_type_text(data.result_type, types));
case .make_closure(let data):
sink.append_line("result|"+"L:"+data.result.id.to_string());
sink.append_line("func_name|"+"X:"+mir_hex(data.func_name));
sink.append_line("captures|"+"len:"+data.captures.len().to_string());
for x in data.captures { sink.append_line("elem|"+mir_operand_text(x, types)); }
sink.append_line("result_type|"+mir_type_text(data.result_type, types));
case .call_closure(let data):
if let x = data.result { sink.append_line("result|"+"L:"+x.id.to_string()); } else { sink.append_line("result|"+"nil"); }
sink.append_line("closure|"+mir_operand_text(data.closure, types));
sink.append_line("args|"+"len:"+data.args.len().to_string());
for x in data.args { sink.append_line("elem|"+mir_operand_text(x, types)); }
sink.append_line("result_type|"+mir_type_text(data.result_type, types));
case .box_existential(let data):
sink.append_line("result|"+"L:"+data.result.id.to_string());
sink.append_line("value|"+mir_operand_text(data.value, types));
sink.append_line("concrete_type|"+mir_type_text(data.concrete_type, types));
sink.append_line("protocol_type|"+mir_type_text(data.protocol_type, types));
sink.append_line("result_type|"+mir_type_text(data.result_type, types));
case .existential_check_type(let data):
sink.append_line("result|"+"L:"+data.result.id.to_string());
sink.append_line("existential|"+mir_operand_text(data.existential, types));
sink.append_line("concrete_type|"+mir_type_text(data.concrete_type, types));
sink.append_line("protocol_type|"+mir_type_text(data.protocol_type, types));
case .existential_unbox(let data):
sink.append_line("result|"+"L:"+data.result.id.to_string());
sink.append_line("existential|"+mir_operand_text(data.existential, types));
sink.append_line("concrete_type|"+mir_type_text(data.concrete_type, types));
sink.append_line("protocol_type|"+mir_type_text(data.protocol_type, types));
sink.append_line("result_type|"+mir_type_text(data.result_type, types));
case .suspend(let data):
sink.append_line("state_id|"+"I:"+data.state_id.to_string());
if let x = data.result { sink.append_line("result|"+"L:"+x.id.to_string()); } else { sink.append_line("result|"+"nil"); }
sink.append_line("result_type|"+mir_type_text(data.result_type, types));
case .task_spawn(let data):
sink.append_line("result|"+"L:"+data.result.id.to_string());
sink.append_line("async_func_name|"+"X:"+mir_hex(data.async_func_name));
sink.append_line("args|"+"len:"+data.args.len().to_string());
for x in data.args { sink.append_line("elem|"+mir_operand_text(x, types)); }
sink.append_line("result_type|"+mir_type_text(data.result_type, types));
if let x = data.frame { sink.append_line("frame|"+mir_operand_text(x, types)); } else { sink.append_line("frame|"+"nil"); }
case .task_join(let data):
if let x = data.result { sink.append_line("result|"+"L:"+x.id.to_string()); } else { sink.append_line("result|"+"nil"); }
sink.append_line("task_handle|"+mir_operand_text(data.task_handle, types));
sink.append_line("result_type|"+mir_type_text(data.result_type, types));
case .task_complete(let data):
sink.append_line("task_handle|"+mir_operand_text(data.task_handle, types));
if let x = data.result { sink.append_line("result|"+mir_operand_text(x, types)); } else { sink.append_line("result|"+"nil"); }
case .alloc_async_frame(let data):
sink.append_line("result|"+"L:"+data.result.id.to_string());
sink.append_line("frame_type|"+mir_type_text(data.frame_type, types));
case .scheduler_run(let data):
if let x = data.until_handle { sink.append_line("until_handle|"+mir_operand_text(x, types)); } else { sink.append_line("until_handle|"+"nil"); }
sink.append_line("destroy_after|"+mir_bool_text(data.destroy_after));
case .task_get_result(let data):
sink.append_line("result|"+"L:"+data.result.id.to_string());
sink.append_line("task_handle|"+mir_operand_text(data.task_handle, types));
sink.append_line("result_type|"+mir_type_text(data.result_type, types));
sink.append_line("consume|"+mir_bool_text(data.consume));
default: {}
} }
pub def mir_format_term(value: MirTerm, types: TypeTable, sink: StringBuilder) -> Void {
sink.append_line("NODE|"+value.kind()); switch value {
case .branch(let data):
sink.append_line("target|"+"K:"+data.target.id.to_string());
case .cond_branch(let data):
sink.append_line("condition|"+mir_operand_text(data.condition, types));
sink.append_line("true_target|"+"K:"+data.true_target.id.to_string());
sink.append_line("false_target|"+"K:"+data.false_target.id.to_string());
case .switch_int(let data):
sink.append_line("value|"+mir_operand_text(data.value, types));
sink.append_line("cases|"+"len:"+data.cases.len().to_string());
for pair in data.cases { sink.append_line("elem|("+"X:"+mir_hex(pair.0)+","+"K:"+pair.1.id.to_string()+")"); }
sink.append_line("default|"+"K:"+data.default.id.to_string());
case .return_stmt(let data):
if let x = data.value { sink.append_line("value|"+mir_operand_text(x, types)); } else { sink.append_line("value|"+"nil"); }
default: {}
} }
def mir_format_local(local: MirLocal, types: TypeTable, sink: StringBuilder) -> Void {
    sink.append_line("LOCAL|L:"+local.id.id.to_string());
    if let symbol = local.symbol_id { sink.append_line("symbol_id|S:"+symbol.id.to_string()); } else { sink.append_line("symbol_id|nil"); }
    sink.append_line("name|X:"+mir_hex(local.name)); sink.append_line("type_id|"+mir_type_text(local.type_id, types));
    sink.append_line("is_mutable|"+mir_bool_text(local.is_mutable)); sink.append_line("is_arg|"+mir_bool_text(local.is_arg));
}
pub def mir_format_fields(program: MirProgram, types: TypeTable, sink: StringBuilder) -> Void {
    for func in program.functions {
        sink.append_line("FUNCTION|X:"+mir_hex(func.name));
        if let symbol = func.symbol_id { sink.append_line("symbol_id|S:"+symbol.id.to_string()); } else { sink.append_line("symbol_id|nil"); }
        sink.append_line("ret_type|"+mir_type_text(func.ret_type, types)); sink.append_line("is_async|"+mir_bool_text(func.is_async)); sink.append_line("is_method|"+mir_bool_text(func.is_method));
        sink.append_line("entry|K:"+func.entry_block.id.to_string()); sink.append_line("args|len:"+func.args.len().to_string());
        for arg in func.args { sink.append_line("elem|L:"+arg.id.id.to_string()); }
        for local in func.locals { mir_format_local(local, types, sink); }
        for id in func.block_order { if let block = func.get_block(id) {
            sink.append_line("BLOCK|K:"+id.id.to_string()); for op in block.ops { mir_format_op(op, types, sink); }
            if let term = block.terminator { mir_format_term(term, types, sink); }
        } }
    }
    for def in program.structs { sink.append_line("STRUCT|X:"+mir_hex(def.name));
        if let symbol = def.symbol_id { sink.append_line("symbol_id|S:"+symbol.id.to_string()); } else { sink.append_line("symbol_id|nil"); }
        sink.append_line("type_id|"+mir_type_text(def.type_id, types));
        for field in def.fields { sink.append_line("FIELD|X:"+mir_hex(field.name)); sink.append_line("type_id|"+mir_type_text(field.type_id, types)); sink.append_line("is_mutable|"+mir_bool_text(field.is_mutable)); }
    }
    for def in program.enums { sink.append_line("ENUM|X:"+mir_hex(def.name));
        if let symbol = def.symbol_id { sink.append_line("symbol_id|S:"+symbol.id.to_string()); } else { sink.append_line("symbol_id|nil"); }
        sink.append_line("type_id|"+mir_type_text(def.type_id, types));
        for item in def.cases { sink.append_line("CASE|X:"+mir_hex(item.name)); sink.append_line("tag|I:"+item.tag.to_string());
            for payload in item.payload_types { if let name = payload.0 { sink.append_line("label|X:"+mir_hex(name)); } else { sink.append_line("label|nil"); } sink.append_line("type_id|"+mir_type_text(payload.1, types)); }
        }
    }
    for def in program.externs { sink.append_line("EXTERN|X:"+mir_hex(def.name));
        if let symbol = def.symbol_id { sink.append_line("symbol_id|S:"+symbol.id.to_string()); } else { sink.append_line("symbol_id|nil"); }
        sink.append_line("abi|X:"+mir_hex(def.abi)); sink.append_line("ret_type|"+mir_type_text(def.ret_type, types));
        for param in def.params { sink.append_line("param|X:"+mir_hex(param.0)); sink.append_line("type_id|"+mir_type_text(param.1, types)); }
    }
}

pub def format_mir_fields(program: MirProgram, types: TypeTable) -> String {
    let sink = StringBuilder.new(); mir_format_fields(program, types, sink); sink.to_string()
}
pub def dump_mir_fields(program: MirProgram, types: TypeTable) -> Void {
    print(format_mir_fields(program, types));
}
