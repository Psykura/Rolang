// expect-error: INVALID_OPERATION: The value of constant 'ORIGIN' must be a constant expression (literals, operators, casts and other co
struct P { var x: i32; }
let ORIGIN = P { x: 0 };
def main() -> i32 { 0 }
