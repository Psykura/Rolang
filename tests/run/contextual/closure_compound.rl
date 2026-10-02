// expect-exit: 1
def main() -> i32 { var total = 0; let add = (x: i32) -> { total += x; }; add(1); total }
