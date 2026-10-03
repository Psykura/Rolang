import std.io
import std.set
struct P: Hashable { let x: i32; }
def same<T: Equatable>(a: T, b: T) -> Bool { a == b }
def hashes<T: Hashable>(a: T) -> u64 { a.hash() }
def main() -> i32 {
    let names: Vec<String?> = [nil, "x", nil];
    let ps: Vec<P?> = [P { x: 1 }, nil];
    let none: String? = nil;
    println(f"{names.contains("x")} {names.contains("y")} {names.contains(none)} {names.index_of(nil) ?? -1} {ps.contains(P { x: 1 })} {ps.contains(P { x: 2 })}");
    let a: i32? = 3; let b: i32? = nil;
    println(f"{same(a, a)} {same(a, b)} {same(b, b)} {hashes(a) == hashes(a)} {hashes(b)}");
    let seen = Set<String?>.new(); seen.add("a"); seen.add("a"); seen.add(nil);
    println(f"{seen.len()}");
    0
}
