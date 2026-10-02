// expect-error: cannot reassign immutable binding 'LIMIT'; use `var` to declare a mutable binding
let LIMIT = 3;
def main() -> i32 { LIMIT = 4; LIMIT }
