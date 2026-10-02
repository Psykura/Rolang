// expect-exit: 15

import "io.rl"

struct Item {
    var n: i32;
    def __release__() -> Void {
        println("deinit");
    }
}

def main() -> i32 {
    let d = Dict<i32, Item>.with_capacity(16, 0);
    d.set(10, Item { n: 1 });
    d.set(20, Item { n: 2 });

    var sum: i32 = 0;
    var i: i32 = 0;
    while i < 5 {
        let a = d.get(10);
        if let av = a {
            sum = sum + av.n;
        }
        let b = d.get(20);
        if let bv = b {
            sum = sum + bv.n;
        }
        i = i + 1;
    }


    println("after free");
    return sum;  // 5 * (1+2) = 15
}
