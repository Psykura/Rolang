// expect-error: Switch on Optional must be exhaustive, missing: nil

def main() -> i32 {
    let x: i32? = nil;
    switch x {
        case .Some(let v): return v;
    }
    return 0;
}
