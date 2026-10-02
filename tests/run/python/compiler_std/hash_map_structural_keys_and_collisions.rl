
import std.hash_map
struct Key { var owner: i32; var name: String; }
def hash(key: Key) -> i64 { return key.owner as i64; }
def equal(a: Key, b: Key) -> Bool {
    return a.owner == b.owner && a.name.equals(b.name);
}
def main() -> i32 {
    let map = HashMap<Key, String>.new(hash, equal);
    var i = 0;
    while i < 100 {
        map.set(Key { owner: i % 3, name: i.to_string() }, "value" + i.to_string());
        i = i + 1;
    }
    if map.len() != 100 { return 1; }
    let snapshot = map.entries();
    map.set(Key { owner: 0, name: "0" }, "changed");
    if map.len() != 100 { return 2; }
    if let value = map.get(Key { owner: 0, name: "0" }) {
        if !value.equals("changed") { return 3; }
    } else { return 4; }
    i = 0;
    while i < 100 {
        let key = Key { owner: i % 3, name: i.to_string() };
        if let removed = map.remove(key) {
            if i != 0 && !removed.equals("value" + i.to_string()) { return 5; }
        } else { return 6; }
        if map.contains(key) { return 7; }
        i = i + 1;
    }
    if !map.is_empty() { return 8; }
    for entry in snapshot {
        if !entry.value.equals("value" + entry.key.name) { return 9; }
    }
    map.set(Key { owner: 5, name: "again" }, "new");
    map.clear();
    if !map.is_empty() { return 10; }
    return 0;
}
