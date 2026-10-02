def main() -> i32 {
    let value: i32? = 3;
    switch value { case .Some(var v): let set = () -> { v = 4; }; set(); case .None: {} }
    0
}
