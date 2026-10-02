// expect-exit: 99

def main() -> i32 {
    let x: i32? = nil;
    switch x {
        case .Some(let v): return v + 10;
        case .None: return 99;
    }
}
