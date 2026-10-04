// expect-error: no enclosing loop is labeled 'outer'
def main() -> i32 {
    for i in 0..<3 { if i == 1 { break outer; } }
    0
}
