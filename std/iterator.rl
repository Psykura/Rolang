// Composable, lazy, single-pass iterators. Copies share cursor state.
// Adapt any source by supplying a closure returning T? to iter_from.
import "vec.rl"

pub struct Iter<T> {
    var advance: () -> T?;
    var finished: Bool;
    pub def __iter__() -> Iter<T> { return self; }
    pub def map<U>(transform: (T) -> U) -> Iter<U> { return iter_map(self, transform); }
    pub def filter(predicate: (T) -> Bool) -> Iter<T> { return iter_filter(self, predicate); }
    pub def take(count: i32) -> Iter<T> { return iter_take(self, count); }
    pub def zip<U>(other: Iter<U>) -> Iter<Zipped<T, U>> { return iter_zip(self, other); }
    pub def collect() -> Vec<T> { return iter_collect(self); }
    pub def fold<U>(initial: U, combine: (U, T) -> U) -> U { return iter_fold(self, initial, combine); }

    pub def __next__() -> T? {
        if self.finished { return nil; }
        let value = self.advance();
        if let item = value { return item; }
        self.finished = true;
        return nil;
    }
}

pub def iter_from<T>(advance: () -> T?) -> Iter<T> {
    return Iter<T> { advance: advance, finished: false };
}

pub def iter_vec<T>(items: Vec<T>) -> Iter<T> {
    let cursor = items.__iter__();
    return iter_from({ cursor.__next__() });
}

struct MapCursor<T, U> {
    var source: Iter<T>;
    var transform: (T) -> U;
    def next() -> U? {
        guard let value = self.source.__next__() else { return nil; }
        return self.transform(value);
    }
}

pub def iter_map<T, U>(source: Iter<T>, transform: (T) -> U) -> Iter<U> {
    let cursor = MapCursor<T, U> { source: source, transform: transform };
    return iter_from({ cursor.next() });
}

struct FilterCursor<T> {
    var source: Iter<T>;
    var predicate: (T) -> Bool;
    def next() -> T? {
        while true {
            guard let value = self.source.__next__() else { return nil; }
            if self.predicate(value) { return value; }
        }
        return nil;
    }
}

pub def iter_filter<T>(source: Iter<T>, predicate: (T) -> Bool) -> Iter<T> {
    let cursor = FilterCursor<T> { source: source, predicate: predicate };
    return iter_from({ cursor.next() });
}

struct TakeCursor<T> {
    var source: Iter<T>;
    var remaining: i32;
    def next() -> T? {
        if self.remaining <= 0 { return nil; }
        self.remaining = self.remaining - 1;
        return self.source.__next__();
    }
}

pub def iter_take<T>(source: Iter<T>, count: i32) -> Iter<T> {
    let cursor = TakeCursor<T> { source: source, remaining: count };
    return iter_from({ cursor.next() });
}

pub struct Indexed<T> { pub var index: i64; pub var value: T; }
struct EnumerateCursor<T> {
    var source: Iter<T>;
    var index: i64;
    def next() -> Indexed<T>? {
        if let value = self.source.__next__() {
            let entry = Indexed<T> { index: self.index, value: value };
            self.index = self.index + 1;
            return entry;
        }
        return nil;
    }
}

pub def iter_enumerate<T>(source: Iter<T>) -> Iter<Indexed<T>> {
    let cursor = EnumerateCursor<T> { source: source, index: 0 };
    return iter_from({ cursor.next() });
}

pub struct Zipped<A, B> { pub var first: A; pub var second: B; }
struct ZipCursor<A, B> {
    var first: Iter<A>;
    var second: Iter<B>;
    def next() -> Zipped<A, B>? {
        let a = self.first.__next__()?;
        let b = self.second.__next__()?;
        return Zipped<A, B> { first: a, second: b };
    }
}

// Stops at the shorter input. A final unmatched first item may be consumed.
pub def iter_zip<A, B>(first: Iter<A>, second: Iter<B>) -> Iter<Zipped<A, B>> {
    let cursor = ZipCursor<A, B> { first: first, second: second };
    return iter_from({ cursor.next() });
}

pub def iter_collect<T>(source: Iter<T>) -> Vec<T> {
    let out = Vec<T>.new();
    for value in source { out.push(value); }
    return out;
}

pub def iter_fold<T, U>(source: Iter<T>, initial: U, combine: (U, T) -> U) -> U {
    var out = initial;
    for value in source { out = combine(out, value); }
    return out;
}

// Import std.iterator to enable this method without a Vec/iterator import cycle.
pub extension<T> Vec<T> {
    pub def iter() -> Iter<T> { return iter_vec(self); }
}

pub extension<T> Iter<T> {
    pub def enumerate() -> Iter<Indexed<T>> { return iter_enumerate(self); }
}
