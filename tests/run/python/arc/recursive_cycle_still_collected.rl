
extern "C" def rt_gc_collect() -> Void;
extern "C" def rt_gc_cycle_count() -> i64;

struct Node { var next: Node?; var tag: i32 }

def make_cycle() {
    // a <-> b cycle, entirely local: both are dead once make_cycle returns.
    var a = Node { next: nil, tag: 1 };
    var b = Node { next: nil, tag: 2 };
    a.next = b;
    b.next = a;
}

def main() -> i32 {
    make_cycle();

    // Push allocations past the GC threshold so a forced collect has work.
    var i = 0;
    while i < 10005 {
        let tmp = Node { next: nil, tag: i };
        i = i + 1;
    }

    // If the cycle was collected, the collector counted >=1 reclaimed object.
    // A leaked cycle (wrongly-acyclic Node) would leave this at 0.
    unsafe {
        rt_gc_collect();
        if rt_gc_cycle_count() > 0 {
            return 0;
        }
    }
    return 1;
}
