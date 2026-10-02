
import std.dict
import std.set
import std.iter
struct Value { var number: i32; }
def main() -> i32 {
    let d = Dict<i32, Value>.with_capacity(2, 0);
    var i = 0;
    while i < 500 { d.set(i, Value { number: i }); i = i + 1; }
    let entries = d.entries();
    let keys = d.keys();
    let values = d.values();
    i = 0;
    while i < 500 {
        if let value = d.remove(i) {
            if value.number != i { return 1; }
        } else { return 2; }
        if d.contains(i) { return 3; }
        if i == 0 && d.keys().get(0) != 1 { return 15; }
        var j = i + 1;
        while j < 500 {
            if let remaining = d.get(j) {
                if remaining.number != j { return 4; }
            } else { return 5; }
            j = j + 1;
        }
        i = i + 1;
    }
    if d.len() != 0 { return 6; }
    if let missing = d.remove(0) { return 7; }
    i = 0;
    while i < 500 {
        if entries.get(i).key != i { return 8; }
        if entries.get(i).value.number != i { return 9; }
        if keys.get(i) != i || values.get(i).number != i { return 10; }
        d.set(i, values.get(i));
        i = i + 1;
    }
    d.clear();
    if d.len() != 0 { return 11; }
    d.set(7, Value { number: 7 });
    for key in dict_keys(d) { if key != 7 { return 12; } }
    let set = Set<String>.new();
    set.add("name");
    let snapshot = set.values();
    if !set.remove("name") || set.remove("name") { return 13; }
    set.add("other");
    set.clear();
    if !set.is_empty() || !snapshot.get(0).equals("name") { return 14; }
    return 0;
}
