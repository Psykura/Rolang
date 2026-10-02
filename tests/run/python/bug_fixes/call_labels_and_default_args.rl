// expect-exit: 42

def add(first x: i32, y: i32 = 2) -> i32 {
    return x + y;
}
def main() -> i32 {
    return add(first: 40);
}
