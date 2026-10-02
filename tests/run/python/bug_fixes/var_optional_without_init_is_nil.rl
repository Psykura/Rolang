// expect-exit: 33

def main() -> i32 {
    var x: i32?;
    switch x {
        case .Some(let v): return v;
        case .None: return 33;
    }
}
