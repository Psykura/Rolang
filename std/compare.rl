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
import "range.rl"

pub protocol Equatable {
    def __eq__(other: Self) -> Bool;
}

pub protocol Comparable: Equatable {
    def __lt__(other: Self) -> Bool;
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
