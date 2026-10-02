// expect-exit: 42

def first() -> String { "hello" }
def second() -> String { "world" }
def main() -> i32 {
    let _ = first();
    let _ = second();
    42
}
