
struct State { var value: i32; }
def fresh(state: State = State { value: 0 }) -> State { return state; }
def emit(name: String, indent: i32 = 2) -> String { return f"{name}:{indent}"; }
def apply<T, U>(value: T, transform: (T) -> U) -> U { return transform(value); }
def labeled(to value: i32 = 42) -> i32 { return value; }
struct Writer { def emit(name: String, indent: i32 = 2) -> String { return emit(name, indent: indent); } }
def main() -> i32 {
    if !emit("node", indent: 4).equals("node:4") { return 1; }
    if !emit(name: "node").equals("node:2") { return 2; }
    if !Writer {}.emit("node", indent: 3).equals("node:3") { return 3; }
    if apply(value: 41, transform: (n) -> { n + 1 }) != 42 { return 4; }
    if labeled() != 42 || labeled(to: 3) != 3 { return 5; }
    let a = fresh(); a.value = 9;
    if fresh().value != 0 || fresh(state: a).value != 9 { return 6; }
    return 0;
}
