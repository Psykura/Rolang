
import std.dict
import std.interner
struct State { var drops: i32; }
struct Item {
    var state: State;
    pub def __release__() -> Void { self.state.drops = self.state.drops + 1; }
}
def exercise(state: State) -> Void {
    let d = Dict<String, Item>.with_capacity(2, 1);
    var i = 0;
    while i < 64 {
        d.set(i.to_string(), Item { state: state });
        i = i + 1;
    }
    let snapshot = d.entries();
    for entry in snapshot { d.remove(entry.key); }
    d.clear();
}
def add_one(d: Dict<String, Item>, state: State) -> Void {
    d.set("a", Item { state: state });
}
def main() -> i32 {
    let state = State { drops: 0 };
    exercise(state);
    if state.drops != 64 { return 1; }
    let d = Dict<String, Item>.with_capacity(2, 1);
    add_one(d, state);
    d.clear();
    if state.drops != 65 { return 2; }
    if let old = d.remove("absent") { return 3; }
    let names = StringInterner.new();
    var i = 0;
    while i < 2000 {
        if names.intern(i.to_string()) != i { return 4; }
        i = i + 1;
    }
    i = 0;
    while i < 2000 {
        if names.intern(i.to_string()) != i { return 5; }
        if let text = names.resolve(i) {
            if !text.equals(i.to_string()) { return 6; }
        } else { return 7; }
        i = i + 1;
    }
    if names.len() != 2000 { return 8; }
    return 0;
}
