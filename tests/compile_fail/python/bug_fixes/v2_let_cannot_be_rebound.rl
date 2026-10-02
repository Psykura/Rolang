// expect-error: INVALID_OPERATION: cannot reassign immutable binding 'x'; use `var` to declare a mutable binding

def main() -> i32 {
    let x: i32 = 1;
    x = 5;
    return x;
}
