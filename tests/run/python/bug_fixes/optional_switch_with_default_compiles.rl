// expect-exit: 5

def main() -> i32 {
    let x: i32? = 5;
    switch x {
        case .Some(let v): return v;
        default: return -1;
    }
}
