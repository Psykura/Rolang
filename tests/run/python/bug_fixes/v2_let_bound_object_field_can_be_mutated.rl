// expect-exit: 42

struct Box {
    var n: i32;
}

def main() -> i32 {
    let b = Box { n: 1 };
    b.n = 42;          // allowed — mutates the heap object, not the binding
    return b.n;
}
