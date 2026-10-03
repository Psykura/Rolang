protocol Make { static def make(n: i32) -> Self; }
struct A: Make { let v: i32; static def make(n: i32) -> A { A { v: n } } }
def pair<A, B>(a: A, b: B) -> A { a }
def main() -> i32 { 0 }
