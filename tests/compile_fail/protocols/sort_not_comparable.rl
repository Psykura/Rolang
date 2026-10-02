// expect-error: 'sort' requires T: Comparable, but Point does not conform: missing __lt__, __eq__
struct Point { let x: i32; }
def main() -> i32 { let points = [Point { x: 1 }]; points.sort(); 0 }
