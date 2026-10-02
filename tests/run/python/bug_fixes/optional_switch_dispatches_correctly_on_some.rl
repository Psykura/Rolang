// expect-exit: 17

def main() -> i32 {
    let x: i32? = 7;
    switch x {
        case .Some(let v): return v + 10;
        case .None: return -1;
    }
}
