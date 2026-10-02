
def call(f: (i32) -> i32, x: i32) -> i32 {
    return f(x);
}

def main() -> i32 {
    let limit = 10;
    let clamp = (x: i32) -> {
        if x > limit {
            return limit;
        }
        var acc = 0;
        var i = 0;
        while i < x {
            acc = acc + 1;
            i = i + 1;
        }
        return acc;
    };
    if call(clamp, 5) != 5 { return 1; }
    if call(clamp, 20) != 10 { return 2; }
    return 0;
}
