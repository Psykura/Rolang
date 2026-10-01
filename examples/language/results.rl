import std.result

def read(valid: Bool) -> Result<i32, String> {
    if valid { return Result<i32, String>.ok(value: 21); }
    Result<i32, String>.err(error: "missing")
}

def twice(valid: Bool) -> Result<i32, String> {
    let n = try read(valid);
    Result<i32, String>.ok(value: n * 2)
}

def main() -> i32 {
    switch twice(true) {
        case .ok(let n): if n != 42 { return 1; }
        case .err(let error): return 2;
    }
    if is_err(twice(false)) { return 0; }
    3
}
