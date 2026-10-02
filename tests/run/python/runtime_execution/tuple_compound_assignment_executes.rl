// expect-exit: 42

def main() -> i32 {
    var t = (a: 10, b: 20);
    t.b += 12;
    t.a + t.b
}
