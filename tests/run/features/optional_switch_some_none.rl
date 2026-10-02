def main() -> i32 { let n: i32? = 42; switch n { case .Some(let x): if x == 42 { return 0; } case .None: return 2; } 1 }
