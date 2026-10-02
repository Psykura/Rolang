// expect-exit: 7

def main() -> i32 {
    let values = ["a": 10, "b": 20];
    if let value = values["c"] {
        return value;
    }
    return 7;
}
