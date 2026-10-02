def sign(n: i32) -> String { let s = if n > 0 { "pos" } else if n < 0 { "neg" } else { "zero" }; s }
def main() -> i32 {
    let x = if 3 > 2 { 40 } else { 0 };
    let y = 2 + if x == 40 { 0 } else { 100 };
    if x + y == 42 && sign(5) == "pos" && sign(-1) == "neg" && sign(0) == "zero" { return 0; }
    1
}
