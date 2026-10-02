// expect-exit: 42

def main() -> i32 {
    let x: i32? = nil;
    switch x {
        case .Some(let v): return v;
        case nil: return 42;
    }
}
