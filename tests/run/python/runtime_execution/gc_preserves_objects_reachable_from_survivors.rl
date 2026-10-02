// expect-exit: 2

extern "C" def rt_gc_collect() -> Void;

struct Node { var next: Node?; var value: i32 }

def main() -> i32 {
    var root = Node { next: nil, value: 1 };
    root.next = Node { next: nil, value: 2 };

    var i = 0;
    while i < 10005 {
        let tmp = Node { next: nil, value: i };
        i = i + 1;
    }

    unsafe { rt_gc_collect(); }

    if let child = root.next {
        return child.value;
    }
    return 99;
}
