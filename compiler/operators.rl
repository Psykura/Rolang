// Operator semantics and lookup tables expressed as switches.
pub import "mir_ops.rl"

pub def is_arithmetic_op(op: String) -> Bool {
    switch op { case "%" | "*" | "+" | "-" | "/": true; default: false; }
}
pub def is_order_comparison_op(op: String) -> Bool {
    switch op { case "<" | "<=" | ">" | ">=": true; default: false; }
}
pub def is_equality_op(op: String) -> Bool {
    switch op { case "!=" | "==": true; default: false; }
}
pub def is_logical_op(op: String) -> Bool {
    switch op { case "&&" | "||": true; default: false; }
}
pub def is_short_circuit_op(op: String) -> Bool {
    switch op { case "&&" | "and" | "or" | "||": true; default: false; }
}
pub def is_short_circuit_and_op(op: String) -> Bool {
    switch op { case "&&" | "and": true; default: false; }
}
pub def is_short_circuit_or_op(op: String) -> Bool {
    switch op { case "or" | "||": true; default: false; }
}
pub def is_bitwise_op(op: String) -> Bool {
    switch op { case "&" | "<<" | ">>" | "^" | "|": true; default: false; }
}
pub def is_nil_coalescing_op(op: String) -> Bool {
    switch op { case "??": true; default: false; }
}
pub def to_method_name(op: String) -> String {
    switch op {
        case "+": "__add__";
        case "-": "__sub__";
        case "*": "__mul__";
        case "/": "__truediv__";
        case "%": "__mod__";
        case "==": "__eq__";
        case "!=": "__ne__";
        case "<": "__lt__";
        case ">": "__gt__";
        case "<=": "__le__";
        case ">=": "__ge__";
        case "&": "__and__";
        case "|": "__or__";
        case "^": "__xor__";
        case "<<": "__lshift__";
        case ">>": "__rshift__";
        default: "";
    }
}
pub def binary_op(op: String) -> BinOpKind? {
    switch op {
        case "+": BinOpKind.add();
        case "-": BinOpKind.sub();
        case "*": BinOpKind.mul();
        case "/": BinOpKind.div();
        case "%": BinOpKind.mod();
        case "&": BinOpKind.bit_and();
        case "|": BinOpKind.bit_or();
        case "^": BinOpKind.bit_xor();
        case "<<": BinOpKind.shl();
        case ">>": BinOpKind.shr();
        default: nil;
    }
}
pub def comparison_op(op: String) -> CmpOpKind? {
    switch op {
        case "==": CmpOpKind.eq();
        case "!=": CmpOpKind.ne();
        case "<": CmpOpKind.lt();
        case "<=": CmpOpKind.le();
        case ">": CmpOpKind.gt();
        case ">=": CmpOpKind.ge();
        default: nil;
    }
}
pub def unary_op(op: String) -> UnaryOpKind? {
    switch op {
        case "-": UnaryOpKind.neg();
        case "!": UnaryOpKind.not();
        case "~": UnaryOpKind.bit_not();
        default: nil;
    }
}
pub def compound_to_base_op(op: String) -> String {
    if op.ends_with("=") { return op.substring(0, (op.len() as i32) - 1); }
    op
}
