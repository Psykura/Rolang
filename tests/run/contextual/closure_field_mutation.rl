struct C { var n: i32; }
def main() -> i32 { let c = C { n: 40 }; var local = 0; let inc = () -> { c.n = c.n + 1; var mine = 1; mine += 1; }; inc(); inc(); if c.n == 42 { return 0; } 1 }
