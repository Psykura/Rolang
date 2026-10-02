// A labeled argument may skip parameters with defaults.
struct Builder {
    var total: i32;
    def add(name: String, short: String = "", help: String = "") -> Builder {
        self.total += (name.len() as i32) + (short.len() as i32) * 10 + (help.len() as i32) * 100;
        self
    }
    static def make(start: i32 = 0, step: i32 = 1, count: i32 = 1) -> i32 { start + step * count }
}

def scale(value: i32, factor: i32 = 2, offset: i32 = 0) -> i32 { value * factor + offset }
def pick<T>(first: T, second: T? = nil, third: T? = nil) -> T { third ?? second ?? first }


def main() -> i32 {
    let builder = Builder { total: 0 };
    builder.add("ab", help: "x").add("c", short: "d");
    if builder.total != 113 { return 1; }
    if scale(5, offset: 1) != 11 { return 2; }
    if scale(value: 5, offset: 3) != 13 { return 3; }
    if Builder.make(count: 3) != 3 || Builder.make(step: 2) != 2 { return 4; }
    if pick(1, third: 3) != 3 || pick("a", third: "c") != "c" { return 5; }
    0
}
