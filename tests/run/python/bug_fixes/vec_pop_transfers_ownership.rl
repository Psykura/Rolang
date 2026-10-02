// expect-exit: 6

import "io.rl"

struct Item {
    var n: i32;
    def __release__() -> Void {
        println("deinit");
    }
}

def main() -> i32 {
    let v = Vec<Item>.new();
    v.push(Item { n: 1 });
    v.push(Item { n: 2 });
    v.push(Item { n: 3 });

    var s: i32 = 0;
    let a = v.pop();
    let b = v.pop();
    let c = v.pop();
    s = a.n + b.n + c.n;


    println("after free");
    return s;  // 1+2+3 = 6
}
