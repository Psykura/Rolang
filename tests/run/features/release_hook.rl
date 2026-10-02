struct C { var hits: i32; }
struct R { var c: C; def __release__() -> Void { self.c.hits = 42; } }
def make(c: C) -> Void { let r = R { c: c }; }
def main() -> i32 { let c = C { hits: 0 }; make(c); if c.hits == 42 { return 0; } 1 }
