def main() -> i32 {
    let value: i32? = 40;
    var result = 0;
    switch value { case .Some(var v): let bump = () -> { v += 2; }; bump(); result = v; case .None: {} }
    if let w = value { let read = () -> { w }; result += read() - 40; }
    for var i in 0..<1 { let inc = () -> { i += 1; }; inc(); result += i - 1; }
    if result == 42 { return 0; }
    1
}
