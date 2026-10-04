import std.io
def classify(n: i32) -> String {
    switch n {
        case -1: "minus one";
        case -10...-2: "negative";
        case 0: "zero";
        case 1..<10: "small";
        case 10...99 | 1000: "medium";
        default: "large";
    }
}
def grade(c: i32) -> String {
    switch c {
        case 'a'...'z': "lower";
        case 'A'...'Z': "upper";
        default: "other";
    }
}
def temperature(t: f64) -> String {
    switch t {
        case -40.0..<0.0: "freezing";
        case 0.0..<25.0: "mild";
        default: "hot";
    }
}
def main() -> i32 {
    for n in [-1, -5, 0, 3, 10, 99, 100, 1000] { println(f"{n}: {classify(n)}"); }
    println(f"{grade('q')} {grade('Q')} {grade('1')}");
    println(f"{temperature(-3.5)} {temperature(20.0)} {temperature(30.0)}");
    let x: i64 = -7;
    switch x { case -9...-5: println("i64 range"); default: println("no"); }
    0
}
