enum D { case n, e, s, w }
def main() -> i32 { let d = D.w; switch d { case .w: return 0; default: return 1; } }
