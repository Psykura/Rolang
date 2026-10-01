// CFG-based MIR for the native compiler.
pub import "mir_forms.rl"
pub import "types.rl"
pub import "symbols.rl"
// Formats a defect detected after type checking, as opposed to an error in the program.
pub def internal_compiler_error(message: String) -> String { "internal compiler error: " + message + " (this is a compiler bug; please report it)" }

pub struct MirLocal {
    pub let id: MirLocalId;
    pub let symbol_id: SymbolId?;
    pub let name: String;
    pub let type_id: TypeId;
    pub let is_mutable: Bool;
    pub let is_arg: Bool;
}
pub struct MirBlock {
    pub let id: MirBlockId;
    pub var ops: Vec<MirOp>;
    pub var terminator: MirTerm?;
    pub def is_terminated() -> Bool { if let term = self.terminator { return true; } false }
}
pub struct MirFunction {
    pub let name: String;
    pub let symbol_id: SymbolId?;
    pub let args: Vec<MirLocal>;
    pub let locals: Vec<MirLocal>;
    pub let ret_type: TypeId;
    pub let blocks: Dict<i32, MirBlock>;
    pub let block_order: Vec<MirBlockId>;
    pub let entry_block: MirBlockId;
    pub let is_async: Bool;
    pub let is_method: Bool;
    pub def get_block(id: MirBlockId) -> MirBlock? {
        self.blocks[id.id]
    }
}
pub struct MirField { pub let name: String; pub let type_id: TypeId; pub let is_mutable: Bool; }
pub struct MirStruct {
    pub let name: String;
    pub let symbol_id: SymbolId?;
    pub let fields: Vec<MirField>;
    pub let type_id: TypeId;
}
pub struct MirEnumCase { pub let name: String; pub let tag: i32; pub let payload_types: Vec<(String?, TypeId)>; }
pub struct MirEnum {
    pub let name: String;
    pub let symbol_id: SymbolId?;
    pub let cases: Vec<MirEnumCase>;
    pub let type_id: TypeId;
}
pub struct MirExternFunc {
    pub let name: String;
    pub let symbol_id: SymbolId?;
    pub let abi: String;
    pub let params: Vec<(String, TypeId)>;
    pub let ret_type: TypeId;
}
pub struct MirProgram {
    pub let functions: Vec<MirFunction>;
    pub let structs: Vec<MirStruct>;
    pub let enums: Vec<MirEnum>;
    pub let externs: Vec<MirExternFunc>;
}
pub struct MirBuildResult {
    pub let program: MirProgram;
    pub let type_table: TypeTable;
    pub let symbol_table: SymbolTable;
    pub let errors: Vec<String>;
    pub def has_errors() -> Bool { self.errors.len() > 0 }
}
pub def mir_constant(kind: MirConstantKind, value: MirScalar, type_id: TypeId) -> MirOperand {
    MirOperand.constant(MirConstant { kind, value, type_id })
}
pub def mir_unit(void_type: TypeId) -> MirOperand { mir_constant(MirConstantKind.unit(), MirScalar.none(), void_type) }
pub def mir_copy(local: MirLocalId, type_id: TypeId) -> MirOperand {
    MirOperand.copy(MirPlace { base: local, projections: Vec<MirProjection>.new(), type_id })
}
pub def mir_operand_type(operand: MirOperand) -> TypeId { operand.type_id() }
pub def mir_targets(term: MirTerm) -> Vec<MirBlockId> {
    let targets = Vec<MirBlockId>.new();
    switch term {
        case .branch(let data): targets.push(data.target);
        case .cond_branch(let data): targets.push(data.true_target); targets.push(data.false_target);
        case .switch_int(let data): for case in data.cases { targets.push(case.1); } targets.push(data.default);
        default: {}
    }
    targets
}
pub def validate_mir_function(func: MirFunction) -> Vec<String> {
    let errors = Vec<String>.new();
    if let entry = func.get_block(func.entry_block) {} else {
        errors.push(f"Function '{func.name}': entry block {func.entry_block.id} does not exist");
    }
    for id in func.block_order { guard let block = func.blocks[id.id] else { continue; }
        guard let term = block.terminator else {
            errors.push(f"Function '{func.name}': block {block.id.id} has no terminator"); continue;
        }
        for target in mir_targets(term) {
            if let destination = func.get_block(target) {} else {
                errors.push(f"Function '{func.name}': block {block.id.id} branches to non-existent block {target.id}");
            }
        }
    }
    errors
}
pub def validate_mir_program(program: MirProgram) -> Vec<String> {
    let errors = Vec<String>.new();
    for func in program.functions { for error in validate_mir_function(func) { errors.push(error); } }
    errors
}
