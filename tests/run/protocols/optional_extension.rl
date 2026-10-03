import std.io

protocol Describe {
    def describe() -> String;
}
extension String: Describe {
    def describe() -> String { f"\"{self}\"" }
}
extension i32: Describe {
    def describe() -> String { self.to_string() }
}
// Optionals describe themselves when their value type does.
extension<Value> Value?: Describe {
    def describe() -> String where Value: Describe {
        if let value = self { return f"some({value.describe()})"; }
        "none"
    }
    def or_else(fallback: Value) -> Value {
        if let value = self { return value; }
        fallback
    }
}

def show<T: Describe>(value: T) -> String { value.describe() }

def main() -> i32 {
    let name: String? = "ro";
    let missing: i32? = nil;
    println(show(name));
    println(show(missing));
    println(f"{missing.or_else(7)} {name.or_else("x")}");
    let items: Vec<String?> = ["a", nil];
    for item in items { println(item.describe()); }
    0
}
