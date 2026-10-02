def f(p: (i32, i32)) -> i32 { switch p { case (0, let y): y; case (let x, _): x; } }
def main() -> i32 { if f((0, 40)) + f((2, 9)) == 42 { return 0; } 1 }
