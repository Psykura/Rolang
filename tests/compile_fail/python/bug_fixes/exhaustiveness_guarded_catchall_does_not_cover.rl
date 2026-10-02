// expect-error: NON_EXHAUSTIVE_MATCH: Switch must be exhaustive, missing cases: Off

enum Light { case On; case Off; }
def f(l: Light) -> i32 {
    switch l {
        case let _ where false: return 1;
        case .On: return 2;
    }
}
def main() -> i32 { return f(Light.On); }
