// expect-error: NON_EXHAUSTIVE_MATCH: Switch must be exhaustive, missing cases: true

def f(b: Bool) -> i32 {
    switch b {
        case true where false: return 1;
        case false: return 2;
    }
}
def main() -> i32 { return f(true); }
