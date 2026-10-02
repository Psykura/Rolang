// expect-exit: 7

import "result.rl"

struct Counter {
    var value: i32;
}

def fail() -> Result<i32, String> {
    return Result.err(error: "boom");
}

def run(c: Counter) -> Result<i32, String> {
    defer {
        c.value = 7;
    }

    let value = fail()?;
    return Result.ok(value: value);
}

def main() -> i32 {
    let c = Counter { value: 0 };
    let _ = run(c);
    return c.value;
}
