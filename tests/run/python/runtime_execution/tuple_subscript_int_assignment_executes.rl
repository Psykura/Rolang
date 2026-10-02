// expect-exit: 42

def main() -> i32 {
    var t = (0, 100);
    t[1] = 42;
    t[0] + t[1]
}
