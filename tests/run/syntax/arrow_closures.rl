def apply(f: (i32) -> i32, v: i32) -> i32 { f(v) }
def main() -> i32 {
    let inc = (n: i32) -> i32 { n + 1 };
    let add = (a: i32, b: i32) -> i32 { a + b };
    let wide = (n: i32) -> i64 { n };
    let unit = () -> i32 { 40 };
    let ctx: (i32) -> i32 = (n) -> i32 { n * 2 };
    if inc(41) == 42 && add(40, 2) == 42 && wide(1) == 1 && unit() == 40 && apply((x: i32) -> i32 { x + 2 }, 40) == 42 && ctx(21) == 42 { return 0; }
    1
}
