// Standard library: equality and ordering protocols and the Vec operations
// that need them (sort, min, max, contains, ...), imported implicitly.
//
// Numbers satisfy both with their operators, Bool is Equatable, and String
// compares bytes. A type conforms by defining the methods:
//
//     struct Version: Comparable {
//         let major: i32; let minor: i32;
//         def __eq__(other: Version) -> Bool { self.major == other.major && self.minor == other.minor }
//         def __lt__(other: Version) -> Bool { self.major < other.major || (self.major == other.major && self.minor < other.minor) }
//     }
//
// Generic code bounded by them can use the operators: with T: Comparable,
// `a < b`, `a > b`, `a <= b` and `a >= b` all derive from __lt__, and
// `a != b` from __eq__.
import "vec.rl"
import "string.rl"
import "range.rl"

pub protocol Equatable {
    def __eq__(other: Self) -> Bool;
}

pub protocol Comparable: Equatable {
    def __lt__(other: Self) -> Bool;
}

// Values usable as Dict keys and Set elements by content: equal values must
// have equal hashes. A struct conforms by defining hash() and __eq__; without
// them, struct keys compare by identity.
pub protocol Hashable: Equatable {
    def hash() -> u64;
}

pub extern "C" def rt_string_hash(value: String) -> u64;
pub extern "C" def rt_f64_bits(value: f64) -> u64;

// Mixes `value` into `seed`, for combining field hashes.
pub def hash_combine(seed: u64, value: u64) -> u64 {
    seed ^ (value + 11400714819323198485 + (seed << 6) + (seed >> 2))
}

def mix_hash(value: u64) -> u64 {
    var z = value + 11400714819323198485;
    z = (z ^ (z >> 30)) * 13787848793156543929;
    z = (z ^ (z >> 27)) * 10723151780598845931;
    z ^ (z >> 31)
}

pub extension i64 { pub def hash() -> u64 { mix_hash(self as u64) } }
pub extension i32 { pub def hash() -> u64 { mix_hash((self as i64) as u64) } }
pub extension i16 { pub def hash() -> u64 { mix_hash((self as i64) as u64) } }
pub extension i8 { pub def hash() -> u64 { mix_hash((self as i64) as u64) } }
pub extension u64 { pub def hash() -> u64 { mix_hash(self) } }
pub extension u32 { pub def hash() -> u64 { mix_hash(self as u64) } }
pub extension u16 { pub def hash() -> u64 { mix_hash(self as u64) } }
pub extension u8 { pub def hash() -> u64 { mix_hash(self as u64) } }
pub extension Bool { pub def hash() -> u64 { if self { return mix_hash(1); } mix_hash(0) } }
// 0.0 and -0.0 are equal and hash alike.
pub extension f64 {
    pub def hash() -> u64 {
        if self == 0.0 { return mix_hash(0); }
        unsafe { return mix_hash(rt_f64_bits(self)); }
    }
}
pub extension f32 { pub def hash() -> u64 { (self as f64).hash() } }
pub extension String: Hashable {
    pub def hash() -> u64 { unsafe { return rt_string_hash(self); } }
}

// Vec operations for comparable elements.
pub extension<T> Vec<T> {
    // Sorts ascending; stable.
    pub def sort() -> Void where T: Comparable { self.sort_by((a, b) -> { a < b }); }
    pub def sorted() -> Vec<T> where T: Comparable { self.sorted_by((a, b) -> { a < b }) }
    // In an ascending vector, an index of `value`, or nil.
    pub def binary_search(value: T) -> i32? where T: Comparable {
        self.binary_search_by((item) -> { if item < value { return -1; } if value < item { return 1; } 0 })
    }
    pub def min() -> T? where T: Comparable {
        if self.len() == 0 { return nil; }
        var best = self.get(0);
        for item in self { if item < best { best = item; } }
        best
    }
    pub def max() -> T? where T: Comparable {
        if self.len() == 0 { return nil; }
        var best = self.get(0);
        for item in self { if item > best { best = item; } }
        best
    }
    pub def contains(value: T) -> Bool where T: Equatable {
        for item in self { if item == value { return true; } }
        false
    }
    pub def index_of(value: T) -> i32? where T: Equatable {
        for index in 0..<self.len() { if self.get(index) == value { return index; } }
        nil
    }
}

// Element-wise equality and hashing.
pub extension<T> Vec<T> {
    pub def __eq__(other: Vec<T>) -> Bool where T: Equatable {
        if self.len() != other.len() { return false; }
        for index in 0..<self.len() { if self.get(index) != other.get(index) { return false; } }
        true
    }
    pub def hash() -> u64 where T: Hashable {
        var seed = mix_hash(self.len() as u64);
        for item in self { seed = hash_combine(seed, item.hash()); }
        seed
    }
}
