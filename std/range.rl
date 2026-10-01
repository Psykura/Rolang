// Integer index ranges. Each for-loop obtains an independent cursor.
pub struct IndexRange {
    pub var start: i32;
    pub var end: i32;
    pub var inclusive: Bool;
    pub def __iter__() -> IndexRangeCursor {
        return IndexRangeCursor { current: self.start, end: self.end, inclusive: self.inclusive, finished: false };
    }
    pub def lower(length: i32) -> i32 {
        if self.start < 0 { return 0; }
        if self.start > length { return length; }
        return self.start;
    }
    pub def upper(length: i32) -> i32 {
        if self.end < 0 { return 0; }
        if self.end >= length { return length; }
        if self.inclusive { return self.end + 1; }
        return self.end;
    }
}

pub struct IndexRangeCursor {
    var current: i32;
    var end: i32;
    var inclusive: Bool;
    var finished: Bool;
    pub def __iter__() -> IndexRangeCursor { return self; }
    pub def __next__() -> i32? {
        if self.finished { return nil; }
        if self.current > self.end || (!self.inclusive && self.current == self.end) {
            self.finished = true; return nil;
        }
        let value = self.current;
        if self.current == self.end { self.finished = true; }
        else { self.current = self.current + 1; }
        return value;
    }
}
