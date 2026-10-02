// expect-exit: 49

import "linked_list.rl"

def main() -> i32 {
    var xs: LinkedList<i32> = LinkedList<i32>.new();
    if !xs.is_empty() { return 1; }

    xs.push_front(10);
    xs.push_front(20);
    xs.push_front(12);

    if xs.len() != 3 { return 2; }
    if (xs.front() ?? 0) != 12 { return 3; }

    let a = xs.pop_front() ?? 0;
    let b = xs.pop_front() ?? 0;
    let c = xs.pop_front() ?? 0;
    let d = xs.pop_front() ?? 7;

    if !xs.is_empty() { return 4; }
    return a + b + c + d;
}
