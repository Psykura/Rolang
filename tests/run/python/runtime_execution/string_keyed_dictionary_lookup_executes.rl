// expect-exit: 20

def main() -> i32 {
    let values = ["a": 10, "b": 20];
    if let value = values["b"] {
        return value;
    }
    return 7;
}
