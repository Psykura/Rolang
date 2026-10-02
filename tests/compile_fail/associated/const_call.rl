// expect-error: The value of constant 'VALUE' must be a constant expression (literals, operators, casts and other con
def compute() -> i32 { 42 }
let VALUE = compute();
def main() -> i32 { VALUE }
