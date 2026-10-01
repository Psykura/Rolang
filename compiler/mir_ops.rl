// Operator kinds used by the full compiler's MIR.
pub enum BinOpKind {
    case add;
    case sub;
    case mul;
    case div;
    case mod;
    case bit_and;
    case bit_or;
    case bit_xor;
    case shl;
    case shr;
    pub def name() -> String {
        switch self {
            case .add: "ADD";
            case .sub: "SUB";
            case .mul: "MUL";
            case .div: "DIV";
            case .mod: "MOD";
            case .bit_and: "BIT_AND";
            case .bit_or: "BIT_OR";
            case .bit_xor: "BIT_XOR";
            case .shl: "SHL";
            case .shr: "SHR";
        }
    }
}
pub enum CmpOpKind {
    case eq;
    case ne;
    case lt;
    case le;
    case gt;
    case ge;
    pub def name() -> String {
        switch self {
            case .eq: "EQ";
            case .ne: "NE";
            case .lt: "LT";
            case .le: "LE";
            case .gt: "GT";
            case .ge: "GE";
        }
    }
}
pub enum UnaryOpKind {
    case neg;
    case not;
    case bit_not;
    pub def name() -> String {
        switch self {
            case .neg: "NEG";
            case .not: "NOT";
            case .bit_not: "BIT_NOT";
        }
    }
}
