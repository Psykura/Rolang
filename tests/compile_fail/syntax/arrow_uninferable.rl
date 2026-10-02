// expect-error: Cannot infer lambda parameter type; add an annotation or a function type context
def main() -> i32 { let f = (x) -> { x + 1 }; 0 }
