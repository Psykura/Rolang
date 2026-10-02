// expect-exit: 9

import "io.rl"
struct Box<T> {
    var value: T;
    def __release__() -> Void { println("released"); }
}
def main() -> i32 {
    let b = Box<i32> { value: 9 };
    let unused = Box<i32> { value: 4 };
    return b.value;
}
