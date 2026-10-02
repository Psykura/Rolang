// expect-exit: 42

def main() -> i32 {
    var t = (a: 0, b: 100);
    t.b = 42;
    t.a + t.b
}
