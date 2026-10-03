import std.io
struct Pair<T> { let a: T; let b: T; def __eq__(other: Pair<T>) -> Bool where T: Equatable { self.a == other.a && self.b == other.b } def hash() -> u64 where T: Hashable { hash_combine(self.a.hash(), self.b.hash()) } }
def main() -> i32 {
    let seen = Dict<Vec<i32>, i32>.new();
    seen[[1, 2]] = 1; seen[[1, 2]] = 2;
    let pairs = Dict<Pair<String>, i32>.new();
    pairs[Pair<String> { a: "x", b: "y" }] = 1; pairs[Pair<String> { a: "x", b: "y" }] = 2;
    println(f"{seen.len()} {pairs.len()}");
    0
}
