def count<T>(items: [T]) -> i32 {
    var n = 0;
    for item in items { let tick = () -> { n += 1; }; tick(); }
    n
}
def main() -> i32 {
    var depth = 0;
    let outer = () -> {
        let inner = () -> { depth += 20; };
        inner(); inner();
    };
    outer();
    if count(["a", "b"]) == 2 && depth == 40 { return 0; }
    1
}
