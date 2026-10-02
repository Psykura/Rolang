
import std.iterator
struct Source {
    var calls: i32;
    def next() -> String? {
        self.calls = self.calls + 1;
        if self.calls < 3 { return self.calls.to_string(); }
        if self.calls == 3 { return nil; }
        return "must not resume";
    }
}
def main() -> i32 {
    let source = Source { calls: 0 };
    let iterator = iter_from(() -> { return source.next(); });
    let alias = iterator;
    if !(iterator.__next__() ?? "").equals("1") { return 1; }
    if !(alias.__next__() ?? "").equals("2") { return 2; }
    if let extra = iterator.__next__() { return 3; }
    if let extra = alias.__next__() { return 4; }
    if source.calls != 3 { return 5; }
    let values = Vec<i32?>.new(); values.push(nil); values.push(42);
    let collected = iter_collect(iter_vec(values));
    if collected.len() != 2 { return 6; }
    if let unexpected = collected.get(0) { return 7; }
    if (collected.get(1) ?? 0) != 42 { return 8; }
    return 0;
}
