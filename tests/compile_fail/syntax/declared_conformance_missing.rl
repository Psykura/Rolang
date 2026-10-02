// expect-error: Type Sq does not conform to Shape; missing requirements: area
protocol Shape { def area() -> i32; }
struct Sq: Shape { var side: i32; }
def total<S: Shape>(s: S) -> i32 { s.area() }
def main() -> i32 { total(Sq { side: 1 }) }
