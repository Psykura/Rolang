// expect-error: cannot cast A to B using `as`. Heap types cannot be reinterpreted as other heap types; construct the 

struct A { var x: i32 }
struct B { var y: i32 }
def main() -> i32 {
    let a = A { x: 1 };
    let b = a as B;
    return b.y;
}
