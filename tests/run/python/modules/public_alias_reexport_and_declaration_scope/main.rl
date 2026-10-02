
import "exports.rl" as Types
typealias Id = String;
def read(id: Types.Id) -> i32 { return id; }
def main() -> i32 {
    let list: Types.List = Vec<i32>.new();
    list.push(42);
    return read(list.get(0)) - 42;
}
