// Checked-in Rolang definitions. Keep node fields, visitors and dumps in sync.
pub import "mir.rl"
import std.string_builder
def mir_print_quote(value: String) -> String {
    let out = StringBuilder.new(); out.append("\"");
    for i in 0..<(value.len() as i32) { let byte = value.byte_at(i);
        if byte == 34 || byte == 92 { out.append_byte(92 as u8); out.append_byte(byte as u8); }
        else if byte == 10 { out.append("\\n"); }
        else if byte == 13 { out.append("\\r"); }
        else if byte == 9 { out.append("\\t"); }
        else { out.append_byte(byte as u8); }
    }
    out.append("\""); out.to_string()
}
def mir_print_place(place: MirPlace, types: TypeTable) -> String {
    var text = "%" + place.base.id.to_string();
    for projection in place.projections { switch projection {
        case .field(let name, _): text += "." + name;
        case .index(let index, _): text += "[" + mir_print_operand(index, types) + "]";
        case .deref(_): text = "*(" + text + ")";
    } } text
}
def mir_print_operand(value: MirOperand, types: TypeTable) -> String { switch value {
    case .copy(let place): return mir_print_place(place, types);
    case .move(let place): return "move " + mir_print_place(place, types);
    case .constant(let constant): switch constant.value {
        case .integer(let x): return x;
        case .floating(let x): return x.to_string();
        case .text(let x): return mir_print_quote(x);
        case .boolean(let x): return x.to_string();
        case .none: switch constant.kind { case .nil: return "nil"; default: return "()"; }
    }
} }

def mir_print_op(value: MirOp, types: TypeTable, sink: StringBuilder) -> Void {
sink.append("    " + value.kind()); switch value {
case .bin_op(let data):
sink.append(" result=");
sink.append("%" + data.result.id.to_string());
sink.append(" op=");
sink.append(data.op.name());
sink.append(" left=");
sink.append(mir_print_operand(data.left, types));
sink.append(" right=");
sink.append(mir_print_operand(data.right, types));
sink.append(" result_type=");
sink.append(types.format_type(data.result_type));
case .cmp_op(let data):
sink.append(" result=");
sink.append("%" + data.result.id.to_string());
sink.append(" op=");
sink.append(data.op.name());
sink.append(" left=");
sink.append(mir_print_operand(data.left, types));
sink.append(" right=");
sink.append(mir_print_operand(data.right, types));
case .unary_op(let data):
sink.append(" result=");
sink.append("%" + data.result.id.to_string());
sink.append(" op=");
sink.append(data.op.name());
sink.append(" operand=");
sink.append(mir_print_operand(data.operand, types));
sink.append(" result_type=");
sink.append(types.format_type(data.result_type));
case .cast_op(let data):
sink.append(" result=");
sink.append("%" + data.result.id.to_string());
sink.append(" operand=");
sink.append(mir_print_operand(data.operand, types));
sink.append(" target_type=");
sink.append(types.format_type(data.target_type));
case .make_struct(let data):
sink.append(" result=");
sink.append("%" + data.result.id.to_string());
sink.append(" struct_type=");
sink.append(types.format_type(data.struct_type));
sink.append(" fields=");
sink.append("["); for i in 0..<data.fields.len() { if i > 0 { sink.append(", "); }
let pair = data.fields[i]; sink.append("(" + mir_print_quote(pair.0) + ", " + mir_print_operand(pair.1, types) + ")");
} sink.append("]");
case .make_enum(let data):
sink.append(" result=");
sink.append("%" + data.result.id.to_string());
sink.append(" enum_type=");
sink.append(types.format_type(data.enum_type));
sink.append(" case_name=");
sink.append(mir_print_quote(data.case_name));
sink.append(" tag=");
sink.append(data.tag.to_string());
sink.append(" payload=");
sink.append("["); for i in 0..<data.payload.len() { if i > 0 { sink.append(", "); }
let x = data.payload[i]; sink.append(mir_print_operand(x, types));
} sink.append("]");
case .make_some(let data):
sink.append(" result=");
sink.append("%" + data.result.id.to_string());
sink.append(" value=");
sink.append(mir_print_operand(data.value, types));
sink.append(" result_type=");
sink.append(types.format_type(data.result_type));
case .make_none(let data):
sink.append(" result=");
sink.append("%" + data.result.id.to_string());
sink.append(" result_type=");
sink.append(types.format_type(data.result_type));
case .extract_field(let data):
sink.append(" result=");
sink.append("%" + data.result.id.to_string());
sink.append(" aggregate=");
sink.append(mir_print_operand(data.aggregate, types));
sink.append(" field_name=");
sink.append(mir_print_quote(data.field_name));
sink.append(" field_index=");
sink.append(data.field_index.to_string());
sink.append(" result_type=");
sink.append(types.format_type(data.result_type));
case .extract_closure_capture(let data):
sink.append(" result=");
sink.append("%" + data.result.id.to_string());
sink.append(" closure=");
sink.append(mir_print_operand(data.closure, types));
sink.append(" capture_index=");
sink.append(data.capture_index.to_string());
sink.append(" result_type=");
sink.append(types.format_type(data.result_type));
case .extract_enum_payload(let data):
sink.append(" result=");
sink.append("%" + data.result.id.to_string());
sink.append(" enum_val=");
sink.append(mir_print_operand(data.enum_val, types));
sink.append(" case_name=");
sink.append(mir_print_quote(data.case_name));
sink.append(" payload_index=");
sink.append(data.payload_index.to_string());
sink.append(" result_type=");
sink.append(types.format_type(data.result_type));
case .get_tag(let data):
sink.append(" result=");
sink.append("%" + data.result.id.to_string());
sink.append(" enum_val=");
sink.append(mir_print_operand(data.enum_val, types));
case .assign(let data):
sink.append(" place=");
sink.append(mir_print_place(data.place, types));
sink.append(" value=");
sink.append(mir_print_operand(data.value, types));
case .store(let data):
sink.append(" place=");
sink.append(mir_print_place(data.place, types));
sink.append(" value=");
sink.append(mir_print_operand(data.value, types));
case .load(let data):
sink.append(" result=");
sink.append("%" + data.result.id.to_string());
sink.append(" place=");
sink.append(mir_print_place(data.place, types));
case .retain(let data):
sink.append(" operand=");
sink.append(mir_print_operand(data.operand, types));
case .release(let data):
sink.append(" operand=");
sink.append(mir_print_operand(data.operand, types));
case .alloc_obj(let data):
sink.append(" result=");
sink.append("%" + data.result.id.to_string());
sink.append(" type_id=");
sink.append(data.type_id.to_string());
sink.append(" payload_size=");
sink.append(data.payload_size.to_string());
sink.append(" result_type=");
sink.append(types.format_type(data.result_type));
case .clone(let data):
sink.append(" result=");
sink.append("%" + data.result.id.to_string());
sink.append(" value=");
sink.append(mir_print_operand(data.value, types));
sink.append(" result_type=");
sink.append(types.format_type(data.result_type));
case .call_static(let data):
sink.append(" result=");
if let x = data.result { sink.append("%" + x.id.to_string()); } else { sink.append("nil"); }
sink.append(" func_name=");
sink.append(mir_print_quote(data.func_name));
sink.append(" func_symbol=");
if let x = data.func_symbol { sink.append("symbol#" + x.id.to_string()); } else { sink.append("nil"); }
sink.append(" args=");
sink.append("["); for i in 0..<data.args.len() { if i > 0 { sink.append(", "); }
let x = data.args[i]; sink.append(mir_print_operand(x, types));
} sink.append("]");
sink.append(" result_type=");
sink.append(types.format_type(data.result_type));
case .call_v_table(let data):
sink.append(" result=");
if let x = data.result { sink.append("%" + x.id.to_string()); } else { sink.append("nil"); }
sink.append(" receiver=");
sink.append(mir_print_operand(data.receiver, types));
sink.append(" method_name=");
sink.append(mir_print_quote(data.method_name));
sink.append(" args=");
sink.append("["); for i in 0..<data.args.len() { if i > 0 { sink.append(", "); }
let x = data.args[i]; sink.append(mir_print_operand(x, types));
} sink.append("]");
sink.append(" result_type=");
sink.append(types.format_type(data.result_type));
case .call_witness(let data):
sink.append(" result=");
if let x = data.result { sink.append("%" + x.id.to_string()); } else { sink.append("nil"); }
sink.append(" witness_type=");
sink.append(types.format_type(data.witness_type));
sink.append(" method_name=");
sink.append(mir_print_quote(data.method_name));
sink.append(" args=");
sink.append("["); for i in 0..<data.args.len() { if i > 0 { sink.append(", "); }
let x = data.args[i]; sink.append(mir_print_operand(x, types));
} sink.append("]");
sink.append(" result_type=");
sink.append(types.format_type(data.result_type));
case .make_closure(let data):
sink.append(" result=");
sink.append("%" + data.result.id.to_string());
sink.append(" func_name=");
sink.append(mir_print_quote(data.func_name));
sink.append(" captures=");
sink.append("["); for i in 0..<data.captures.len() { if i > 0 { sink.append(", "); }
let x = data.captures[i]; sink.append(mir_print_operand(x, types));
} sink.append("]");
sink.append(" result_type=");
sink.append(types.format_type(data.result_type));
case .call_closure(let data):
sink.append(" result=");
if let x = data.result { sink.append("%" + x.id.to_string()); } else { sink.append("nil"); }
sink.append(" closure=");
sink.append(mir_print_operand(data.closure, types));
sink.append(" args=");
sink.append("["); for i in 0..<data.args.len() { if i > 0 { sink.append(", "); }
let x = data.args[i]; sink.append(mir_print_operand(x, types));
} sink.append("]");
sink.append(" result_type=");
sink.append(types.format_type(data.result_type));
case .box_existential(let data):
sink.append(" result=");
sink.append("%" + data.result.id.to_string());
sink.append(" value=");
sink.append(mir_print_operand(data.value, types));
sink.append(" concrete_type=");
sink.append(types.format_type(data.concrete_type));
sink.append(" protocol_type=");
sink.append(types.format_type(data.protocol_type));
sink.append(" result_type=");
sink.append(types.format_type(data.result_type));
case .existential_check_type(let data):
sink.append(" result=");
sink.append("%" + data.result.id.to_string());
sink.append(" existential=");
sink.append(mir_print_operand(data.existential, types));
sink.append(" concrete_type=");
sink.append(types.format_type(data.concrete_type));
sink.append(" protocol_type=");
sink.append(types.format_type(data.protocol_type));
case .existential_unbox(let data):
sink.append(" result=");
sink.append("%" + data.result.id.to_string());
sink.append(" existential=");
sink.append(mir_print_operand(data.existential, types));
sink.append(" concrete_type=");
sink.append(types.format_type(data.concrete_type));
sink.append(" protocol_type=");
sink.append(types.format_type(data.protocol_type));
sink.append(" result_type=");
sink.append(types.format_type(data.result_type));
case .suspend(let data):
sink.append(" state_id=");
sink.append(data.state_id.to_string());
sink.append(" result=");
if let x = data.result { sink.append("%" + x.id.to_string()); } else { sink.append("nil"); }
sink.append(" result_type=");
sink.append(types.format_type(data.result_type));
case .task_spawn(let data):
sink.append(" result=");
sink.append("%" + data.result.id.to_string());
sink.append(" async_func_name=");
sink.append(mir_print_quote(data.async_func_name));
sink.append(" args=");
sink.append("["); for i in 0..<data.args.len() { if i > 0 { sink.append(", "); }
let x = data.args[i]; sink.append(mir_print_operand(x, types));
} sink.append("]");
sink.append(" result_type=");
sink.append(types.format_type(data.result_type));
sink.append(" frame=");
if let x = data.frame { sink.append(mir_print_operand(x, types)); } else { sink.append("nil"); }
case .task_join(let data):
sink.append(" result=");
if let x = data.result { sink.append("%" + x.id.to_string()); } else { sink.append("nil"); }
sink.append(" task_handle=");
sink.append(mir_print_operand(data.task_handle, types));
sink.append(" result_type=");
sink.append(types.format_type(data.result_type));
case .task_complete(let data):
sink.append(" task_handle=");
sink.append(mir_print_operand(data.task_handle, types));
sink.append(" result=");
if let x = data.result { sink.append(mir_print_operand(x, types)); } else { sink.append("nil"); }
case .alloc_async_frame(let data):
sink.append(" result=");
sink.append("%" + data.result.id.to_string());
sink.append(" frame_type=");
sink.append(types.format_type(data.frame_type));
case .scheduler_run(let data):
sink.append(" until_handle=");
if let x = data.until_handle { sink.append(mir_print_operand(x, types)); } else { sink.append("nil"); }
sink.append(" destroy_after=");
sink.append(data.destroy_after.to_string());
case .task_get_result(let data):
sink.append(" result=");
sink.append("%" + data.result.id.to_string());
sink.append(" task_handle=");
sink.append(mir_print_operand(data.task_handle, types));
sink.append(" result_type=");
sink.append(types.format_type(data.result_type));
sink.append(" consume=");
sink.append(data.consume.to_string());
default: {}
} sink.append_line(""); }
def mir_print_term(value: MirTerm, types: TypeTable, sink: StringBuilder) -> Void {
switch value {
                case .cond_branch(let data): sink.append_line("    if " + mir_print_operand(data.condition, types) + " then bb" + data.true_target.id.to_string() + " else bb" + data.false_target.id.to_string()); return;
                case .return_stmt(let data): var text = "    return"; if let x = data.value { text += " " + mir_print_operand(x, types); } sink.append_line(text); return;
                default: {}
            }
sink.append("    " + value.kind()); switch value {
case .branch(let data):
sink.append(" target=");
sink.append("bb" + data.target.id.to_string());
case .cond_branch(let data):
sink.append(" condition=");
sink.append(mir_print_operand(data.condition, types));
sink.append(" true_target=");
sink.append("bb" + data.true_target.id.to_string());
sink.append(" false_target=");
sink.append("bb" + data.false_target.id.to_string());
case .switch_int(let data):
sink.append(" value=");
sink.append(mir_print_operand(data.value, types));
sink.append(" cases=");
sink.append("["); for i in 0..<data.cases.len() { if i > 0 { sink.append(", "); }
let pair = data.cases[i]; sink.append("(" + mir_print_quote(pair.0) + ", " + "bb" + pair.1.id.to_string() + ")");
} sink.append("]");
sink.append(" default=");
sink.append("bb" + data.default.id.to_string());
case .return_stmt(let data):
sink.append(" value=");
if let x = data.value { sink.append(mir_print_operand(x, types)); } else { sink.append("nil"); }
default: {}
} sink.append_line(""); }
pub def format_mir(program: MirProgram, types: TypeTable) -> String {
        let sink = StringBuilder.new();
        for item in program.structs {
            sink.append_line("struct " + item.name + " {");
            for field in item.fields { var prefix = "let "; if field.is_mutable { prefix = "var "; } sink.append_line("  " + prefix + field.name + ": " + types.format_type(field.type_id)); }
            sink.append_line("}");
        }
        for item in program.enums {
            sink.append_line("enum " + item.name + " {");
            for entry in item.cases { sink.append("  case " + entry.name + "(");
                for i in 0..<entry.payload_types.len() { if i > 0 { sink.append(", "); } let pair = entry.payload_types[i]; if let label = pair.0 { sink.append(label + ": "); } sink.append(types.format_type(pair.1)); }
                sink.append_line(") = " + entry.tag.to_string());
            } sink.append_line("}");
        }
        for item in program.externs { sink.append("extern " + mir_print_quote(item.abi) + " def " + item.name + "(");
            for i in 0..<item.params.len() { if i > 0 { sink.append(", "); } let pair = item.params[i]; sink.append(pair.0 + ": " + types.format_type(pair.1)); }
            sink.append_line(") -> " + types.format_type(item.ret_type));
        }
        for func in program.functions {
            sink.append("def " + func.name + "(");
            for i in 0..<func.args.len() { if i > 0 { sink.append(", "); } let arg = func.args[i]; sink.append(arg.name + "=%" + arg.id.id.to_string() + ": " + types.format_type(arg.type_id)); }
            sink.append(")"); if func.is_async { sink.append(" async"); }
            sink.append_line(" -> " + types.format_type(func.ret_type) + " {");
            for local in func.locals { if !local.is_arg { sink.append_line("  local %" + local.id.id.to_string() + " " + local.name + ": " + types.format_type(local.type_id)); } }
            for id in func.block_order { if let block = func.get_block(id) {
                sink.append_line("  bb" + id.id.to_string() + ":");
                for op in block.ops { mir_print_op(op, types, sink); }
                if let term = block.terminator { mir_print_term(term, types, sink); }
            } } sink.append_line("}");
        } sink.to_string()
    }
