// expect-exit: 30

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

    // Read each element a few times. If the runtime UAF were still present,
    // these reads would either double-free or read freed memory.
    var sum: i32 = 0;
    var i: i32 = 0;
    while i < 5 {
        let a = v.get(0);
        let b = v.get(1);
        let c = v.get(2);
        sum = sum + a.n + b.n + c.n;
        i = i + 1;
    }

    // Now drop the Vec; the items should be deinit'd exactly once each.

    println("after free");
    return sum;  // 5 * (1+2+3) = 30
}
