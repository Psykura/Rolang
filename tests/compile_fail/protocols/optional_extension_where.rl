// expect-error: requires Value: Describe, but Bool does not conform
protocol Describe {
    def describe() -> String;
}
extension<Value> Value?: Describe {
    def describe() -> String where Value: Describe {
        if let value = self { return value.describe(); }
        "none"
    }
}
def show<T: Describe>(value: T) -> String { value.describe() }
def main() -> i32 {
    let flag: Bool? = true;
    show(flag);
    0
}
