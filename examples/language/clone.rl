struct Counter { var value: i32; }
struct Box { var counter: Counter; var tag: i32; }

def main() -> i32 {
    let counter = Counter { value: 1 };
    let first = Box { counter, tag: 10 };
    let second = first.clone();
    second.tag = 20;
    second.counter.value = 42;
    if first.tag == 10 && first.counter.value == 42 { return 0; }
    1
}
