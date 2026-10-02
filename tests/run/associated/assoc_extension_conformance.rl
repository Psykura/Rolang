protocol Source { associatedtype Output; def next() -> Output?; }
struct Counter { var n: i32; }
extension Counter: Source { def next() -> i32? { if self.n >= 3 { return nil; } self.n += 1; self.n } }
def drain<S: Source>(s: S) -> i32 { var count = 0; var going = true; while going { if let v = s.next() { count += 1; } else { going = false; } } count }
def main() -> i32 { if drain(Counter { n: 0 }) == 3 { return 0; } 1 }
