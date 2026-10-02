// expect-error: INVALID_OPERATION: cannot reassign immutable binding 'n'; use `var` to declare a mutable binding
def main() -> i32 { let n = 1; let f = () -> { n = 2; }; f(); 0 }
