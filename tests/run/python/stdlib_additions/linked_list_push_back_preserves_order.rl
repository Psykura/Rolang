// expect-exit: 35

import "linked_list.rl"

def main() -> i32 {
    var xs: LinkedList<i32> = LinkedList<i32>.new();
    xs.push_back(5);
    xs.push_back(10);
    xs.push_back(20);

    let a = xs.pop_front() ?? 0;
    let b = xs.pop_front() ?? 0;
    let c = xs.pop_front() ?? 0;

    return a + b + c;
}
