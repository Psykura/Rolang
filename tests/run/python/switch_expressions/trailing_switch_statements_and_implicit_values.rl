
struct State { var count: i32; }
def set(s: State, value: Bool) -> Void {
    switch value { case true: s.count = 40; case false: s.count = 0; }
}
def add(s: State, value: Bool) -> Void {
    switch value { case true: set(s, true); case false: set(s, false); }
}
def choose(value: Bool) -> i32 {
    switch value { case true: 2; case false: 0; }
}
def main() -> i32 {
    let s = State { count: 0 }; add(s, true);
    return s.count + choose(true) - 42;
}
