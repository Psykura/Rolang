// expect-exit: 10

def main() -> i32 {
    var total = 0;
    for x in [1, 2, 3, 4] {
        total = total + x;
    }
    return total;
}
