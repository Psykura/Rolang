
import std.hash_map
struct Salt { var value: i64; }
def make_map() -> HashMap<i32, String> {
    let salt = Salt { value: 17 };
    let hash = (key: i32) -> { return (key as i64) + salt.value; };
    let equal = (a: i32, b: i32) -> { return a == b; };
    return HashMap<i32, String>.new(hash, equal);
}
def main() -> i32 {
    let map = make_map();
    map.set(7, "seven");
    if let result = map.get(7) { if !result.equals("seven") { return 1; } }
    else { return 2; }
    return 0;
}
