// expect-error: Switch on Optional must be exhaustive, missing: Some(...)

enum E { case A(i32); case B(i32); }
def wrap() -> E? { return E.A(1); }
def main() -> i32 {
    let r = wrap();
    switch r {
        case .Some(.A(let v)): return v;
        case nil: return 99;
    }
}
