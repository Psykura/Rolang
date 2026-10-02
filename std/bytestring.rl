import "range.rl"
// Standard library: pure Rolang byte strings.
//
// It stores UTF-8 bytes directly in Vec<u8>. Unicode scalar / grapheme APIs are
// intentionally out of scope for now; byte values are primitive numbers.

import "vec.rl"

pub struct ByteString {
    var bytes: Vec<u8>;

    pub static def new() -> ByteString {
        return ByteString { bytes: Vec<u8>.new() };
    }

    pub static def with_capacity(capacity: i32) -> ByteString {
        return ByteString { bytes: Vec<u8>.with_capacity(capacity) };
    }

    pub static def from_byte(byte: u8) -> ByteString {
        var result = ByteString.with_capacity(1);
        result.push(byte);
        return result;
    }

    pub def len() -> i32 {
        return self.bytes.len();
    }

    pub def is_empty() -> Bool {
        return self.bytes.len() == 0;
    }

    pub def push(byte: u8) -> Void {
        self.bytes.push(byte);
    }

    pub def byte_at(index: i32) -> u8 {
        return self.bytes.get(index);
    }

    pub def equals(other: ByteString) -> Bool {
        let n = self.len();
        if n != other.len() { return false; }
        for i in 0..<n {
            if self.byte_at(i) != other.byte_at(i) { return false; }
        }
        return true;
    }

    pub def compare_to(other: ByteString) -> i32 {
        let a_len = self.len();
        let b_len = other.len();
        var limit = a_len;
        if b_len < limit { limit = b_len; }

        for i in 0..<limit {
            let a = self.byte_at(i) as i32;
            let b = other.byte_at(i) as i32;
            if a < b { return -1; }
            if a > b { return 1; }
        }

        if a_len < b_len { return -1; }
        if a_len > b_len { return 1; }
        return 0;
    }

    pub def starts_with(prefix: ByteString) -> Bool {
        let n = prefix.len();
        if n > self.len() { return false; }
        for i in 0..<n {
            if self.byte_at(i) != prefix.byte_at(i) { return false; }
        }
        return true;
    }

    pub def ends_with(suffix: ByteString) -> Bool {
        let n = suffix.len();
        let self_len = self.len();
        if n > self_len { return false; }
        let start = self_len - n;
        for i in 0..<n {
            if self.byte_at(start + i) != suffix.byte_at(i) { return false; }
        }
        return true;
    }

    pub def contains(needle: ByteString) -> Bool {
        return self.find(needle) >= 0;
    }

    pub def find(needle: ByteString) -> i32 {
        let n = needle.len();
        if n == 0 { return 0; }
        let self_len = self.len();
        if n > self_len { return -1; }

        var i = 0;
        let last = self_len - n;
        while i <= last {
            var j = 0;
            var matched = true;
            while j < n {
                if self.byte_at(i + j) != needle.byte_at(j) {
                    matched = false;
                    break;
                }
                j = j + 1;
            }
            if matched { return i; }
            i = i + 1;
        }
        return -1;
    }

    pub def substring(start: i32, count: i32) -> ByteString {
        var result = ByteString.with_capacity(count);
        if start < 0 { return result; }
        if count <= 0 { return result; }

        let self_len = self.len();
        if start >= self_len { return result; }

        var i = 0;
        while i < count && start + i < self_len {
            result.push(self.byte_at(start + i));
            i = i + 1;
        }
        return result;
    }

    pub def concat(other: ByteString) -> ByteString {
        var result = ByteString.with_capacity(self.len() + other.len());
        var i = 0;
        while i < self.len() {
            result.push(self.byte_at(i));
            i = i + 1;
        }
        i = 0;
        while i < other.len() {
            result.push(other.byte_at(i));
            i = i + 1;
        }
        return result;
    }

    pub def repeat(count: i32) -> ByteString {
        if count <= 0 { return ByteString.new(); }
        var result = ByteString.with_capacity(self.len() * count);
        for n in 0..<count {
            for i in 0..<self.len() {
                result.push(self.byte_at(i));
            }
        }
        return result;
    }

    pub def trim_ascii() -> ByteString {
        let n = self.len();
        var start = 0;
        while start < n && is_ascii_space(self.byte_at(start)) {
            start = start + 1;
        }

        var end = n - 1;
        while end >= start && is_ascii_space(self.byte_at(end)) {
            end = end - 1;
        }

        if end < start { return ByteString.new(); }
        return self.substring(start, end - start + 1);
    }
}

def is_ascii_space(byte: u8) -> Bool {
    let b = byte as i32;
    return b == 32 || b == 9 || b == 10 || b == 13;
}
