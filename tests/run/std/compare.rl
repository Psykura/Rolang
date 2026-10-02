import std.io
struct Version: Comparable {
    let major: i32; let minor: i32;
    def __eq__(other: Version) -> Bool { self.major == other.major && self.minor == other.minor }
    def __lt__(other: Version) -> Bool { self.major < other.major || (self.major == other.major && self.minor < other.minor) }
    def to_string() -> String { f"{self.major}.{self.minor}" }
}
def largest<T: Comparable>(values: Vec<T>) -> T {
    var best = values[0];
    for value in values { if value > best { best = value; } }
    best
}
def same<T: Equatable>(a: T, b: T) -> Bool { a == b && !(a != b) }
def main() -> i32 {
    let numbers = [5, 3, 9, 1, 7];
    numbers.sort();
    println(f"{numbers[0]} {numbers[4]} {largest([2.5, 9.5, 1.0])} {largest(["pear", "apple", "zoo"])}");
    let versions = [Version { major: 1, minor: 2 }, Version { major: 0, minor: 9 }, Version { major: 1, minor: 0 }];
    let sorted = versions.sorted();
    println(f"{sorted[0]} {sorted[2]} {largest(versions)} {versions.min()?.to_string() ?? "-"} {versions.max()?.to_string() ?? "-"}");
    println(f"{numbers.contains(7)} {numbers.contains(4)} {numbers.index_of(9) ?? -1} {numbers.binary_search(5) ?? -1} {["a", "b"].contains("b")}");
    println(f"{same(3, 3)} {same(true, false)} {same(Version { major: 1, minor: 0 }, Version { major: 1, minor: 0 })}");
    let a = Version { major: 2, minor: 0 }; let b = Version { major: 1, minor: 5 };
    println(f"{a > b} {a <= b} {a >= b} {a != b}");
    0
}
