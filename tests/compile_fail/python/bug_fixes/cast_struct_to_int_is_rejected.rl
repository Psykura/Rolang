// expect-error: cannot cast P to i32 using `as`. Heap types cannot be reinterpreted as integers.

struct P { var x: i32 }
def main() -> i32 {
    let p = P { x: 1 };
    return p as i32;
}
