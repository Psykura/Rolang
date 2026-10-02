// expect-error: NON_EXHAUSTIVE_MATCH: Switch must be exhaustive, missing cases: Red

enum Color { case Red; case Green; case Blue; }
def describe(c: Color) -> i32 {
    switch c {
        case .Red where false: return 1;
        case .Green: return 2;
        case .Blue: return 3;
    }
}
def main() -> i32 { return describe(Color.Red); }
