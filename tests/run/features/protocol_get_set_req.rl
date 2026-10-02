protocol Named { var id: i32 { get set }; }
struct T { var id: i32; }
extension T: Named {}
def bump<X: Named>(x: X) -> i32 { x.id = x.id + 1; x.id }
def main() -> i32 { if bump(T { id: 41 }) == 42 { return 0; } 1 }
