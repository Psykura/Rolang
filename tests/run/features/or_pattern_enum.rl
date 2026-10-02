enum D { case n; case e; case s; case w; }
def vertical(d: D) -> Bool { switch d { case .n | .s: true; default: false; } }
def main() -> i32 { if vertical(D.n) && !vertical(D.e) { return 0; } 1 }
