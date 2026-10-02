// Shared type-checking results and errors.
pub import "ids.rl"
pub import "source.rl"
import "types.rl"

pub enum CalleeKind {
    case indirect; case static_call; case method; case vtable; case witness; case enum_ctor;

    pub def name() -> String {
        switch self {
            case .indirect: "INDIRECT"; case .static_call: "STATIC";
            case .method: "METHOD"; case .vtable: "VTABLE";
            case .witness: "WITNESS"; case .enum_ctor: "ENUM_CTOR";
        }
    }
}

pub struct CalleeId {
    pub var kind: CalleeKind;
    pub var symbol_id: SymbolId? = nil;
    pub var case_name: String? = nil;
}

pub enum TypeErrorKind {
    case type_mismatch; case undefined_member; case not_callable;
    case wrong_arg_count; case wrong_arg_type; case cannot_infer;
    case not_assignable; case invalid_operation; case non_exhaustive_match;
    case not_a_type; case generic_arg_count; case not_a_protocol;
    case protocol_not_satisfied; case duplicate_member;

    pub def name() -> String {
        switch self {
            case .type_mismatch: "TYPE_MISMATCH";
            case .undefined_member: "UNDEFINED_MEMBER";
            case .not_callable: "NOT_CALLABLE";
            case .wrong_arg_count: "WRONG_ARG_COUNT";
            case .wrong_arg_type: "WRONG_ARG_TYPE";
            case .cannot_infer: "CANNOT_INFER";
            case .not_assignable: "NOT_ASSIGNABLE";
            case .invalid_operation: "INVALID_OPERATION";
            case .non_exhaustive_match: "NON_EXHAUSTIVE_MATCH";
            case .not_a_type: "NOT_A_TYPE";
            case .generic_arg_count: "GENERIC_ARG_COUNT";
            case .not_a_protocol: "NOT_A_PROTOCOL";
            case .protocol_not_satisfied: "PROTOCOL_NOT_SATISFIED";
            case .duplicate_member: "DUPLICATE_MEMBER";
        }
    }
}

pub struct TypeError {
    pub var kind: TypeErrorKind;
    pub var message: String;
    pub var span: Span? = nil;

    pub def to_string() -> String {
        var location = "";
        if let span = self.span { location = f" at line {span.line}, column {span.column}"; }
        f"{self.kind.name()}: {self.message}{location}"
    }
}

pub struct TypeCheckResult {
    pub let type_table: TypeTable;
    pub let expr_types: Dict<i32, TypeId>;
    pub let call_targets: Dict<i32, CalleeId>;
    pub let operator_targets: Dict<i32, CalleeId>;
    pub let errors: Vec<TypeError>;
    pub let member_method_symbols: Dict<i32, SymbolId>;
    pub let lowered_expressions: Dict<i32, NodeId>;
    pub let intrinsic_types: Dict<i32, TypeId>;
    pub let intrinsic_values: Dict<i32, i64>;
    pub let propagation_error_types: Dict<i32, TypeId>;
    // Element type of each for-loop, keyed by the loop statement.
    pub let loop_element_types: Dict<i32, TypeId>;

    pub static def new(type_table: TypeTable) -> TypeCheckResult {
        TypeCheckResult {
            type_table,
            expr_types: Dict<i32, TypeId>.with_capacity(16, 0),
            call_targets: Dict<i32, CalleeId>.with_capacity(16, 0),
            operator_targets: Dict<i32, CalleeId>.with_capacity(16, 0),
            errors: Vec<TypeError>.new(),
            member_method_symbols: Dict<i32, SymbolId>.with_capacity(16, 0),
            lowered_expressions: Dict<i32, NodeId>.with_capacity(16, 0),
            intrinsic_types: Dict<i32, TypeId>.with_capacity(16, 0),
            intrinsic_values: Dict<i32, i64>.with_capacity(16, 0),
            propagation_error_types: Dict<i32, TypeId>.with_capacity(16, 0),
            loop_element_types: Dict<i32, TypeId>.with_capacity(16, 0)
        }
    }

    pub def has_errors() -> Bool { self.errors.len() > 0 }
    pub def get_expr_type(expr: NodeId) -> TypeId? { self.expr_types[expr.id] }
}
