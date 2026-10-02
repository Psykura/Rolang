import "range.rl"
// Standard library: heap-backed strings.
//
// `String` is a normal ARC-managed Rolang struct. Its bytes live behind an
// opaque runtime handle because Rolang source cannot safely manipulate raw
// buffers yet. String literals and runtime string-producing helpers create a
// fresh handle, and the deinit block releases it.

import "vec.rl"

pub extern "C" def rt_string_free_data(data: RawPtr) -> Void;
pub extern "C" def rt_string_handle_data(handle: RawPtr) -> RawPtr;
pub extern "C" def rt_string_handle_len(handle: RawPtr) -> i64;
pub extern "C" def rt_string_free_handle_only(handle: RawPtr) -> Void;
pub extern "C" def rt_string_len(s: String) -> i64;
pub extern "C" def rt_string_is_empty(s: String) -> i64;
pub extern "C" def rt_string_compare(a: String, b: String) -> i32;
pub extern "C" def rt_string_contains(haystack: String, needle: String) -> i32;
pub extern "C" def rt_string_starts_with(s: String, prefix: String) -> i32;
pub extern "C" def rt_string_ends_with(s: String, suffix: String) -> i32;
pub extern "C" def rt_string_concat_handle(a: String, b: String) -> RawPtr;
pub extern "C" def rt_int_to_string_handle(value: i64) -> RawPtr;
pub extern "C" def rt_f64_to_string_handle(value: f64) -> RawPtr;
pub extern "C" def rt_string_repeat_handle(s: String, count: i32) -> RawPtr;
pub extern "C" def rt_string_char_at(s: String, index: i32) -> i32;
pub extern "C" def rt_string_find_char(s: String, ch: i32, start: i32) -> i32;
pub extern "C" def rt_string_substring_handle(s: String, start: i32, len: i32) -> RawPtr;
pub extern "C" def rt_string_trim_handle(s: String) -> RawPtr;
pub extern "C" def rt_string_replace_handle(s: String, old: String, new_val: String) -> RawPtr;
pub extern "C" def rt_string_to_i64(s: String) -> i64;
pub extern "C" def rt_string_to_i32(s: String) -> i32;
pub extern "C" def rt_string_to_f64(s: String) -> f64;

pub extern "C" def rt_string_scalar_at(s: String, offset: i32) -> i32;
pub extern "C" def rt_string_scalar_width(s: String, offset: i32) -> i32;
pub extern "C" def rt_string_grapheme_end(s: String, offset: i32) -> i32;
pub extern "C" def rt_string_is_valid_utf8(s: String) -> i32;
pub extern "C" def rt_string_from_scalar_handle(scalar: i32) -> RawPtr;

pub struct String {
    var data: RawPtr;
    var length: i64;
    // Lazily memoized content hash, written by the runtime dict the first
    // time this string is used as a key (0 = not yet computed). String
    // contents are immutable after construction, so the cache never goes
    // stale. Field order matters: the C runtime reads {data, length, hash}
    // at payload offsets 0/8/16 (StringPayload in std/string.h), and the
    // string-literal emission in compiler/codegen/backend.rl uses the same layout.
    var hash_cache: i64;

    pub unsafe static def from_handle(handle: RawPtr) -> String {
        unsafe {
            let data = rt_string_handle_data(handle);
            let len = rt_string_handle_len(handle);
            rt_string_free_handle_only(handle);
            return String { data: data, length: len, hash_cache: 0 };
        }
    }

    pub def __release__() -> Void {
        unsafe { rt_string_free_data(self.data); }
    }

    pub def len() -> i64 {
        return self.length;
    }

    pub def is_empty() -> Bool {
        return self.length == 0;
    }

    pub def equals(other: String) -> Bool {
        unsafe { return rt_string_compare(self, other) == 0; }
    }

    // Java-style lexicographic comparison: <0, 0, >0.
    pub def compare_to(other: String) -> i32 {
        unsafe { return rt_string_compare(self, other); }
    }

    pub def contains(needle: String) -> Bool {
        unsafe { return rt_string_contains(self, needle) != 0; }
    }

    pub def starts_with(prefix: String) -> Bool {
        unsafe { return rt_string_starts_with(self, prefix) != 0; }
    }

    pub def ends_with(suffix: String) -> Bool {
        unsafe { return rt_string_ends_with(self, suffix) != 0; }
    }

    pub def concat(other: String) -> String {
        unsafe { return String.from_handle(rt_string_concat_handle(self, other)); }
    }

    pub def __add__(other: String) -> String {
        return self.concat(other);
    }

    // Byte-wise content comparison for ==, != and ordering operators.
    pub def __eq__(other: String) -> Bool { self.equals(other) }
    pub def __ne__(other: String) -> Bool { !self.equals(other) }
    pub def __lt__(other: String) -> Bool { self.compare_to(other) < 0 }
    pub def __le__(other: String) -> Bool { self.compare_to(other) <= 0 }
    pub def __gt__(other: String) -> Bool { self.compare_to(other) > 0 }
    pub def __ge__(other: String) -> Bool { self.compare_to(other) >= 0 }

    // ---- Unicode views; the byte-oriented APIs above are unchanged ----

    // Unicode scalar values (code points). Each invalid UTF-8 byte reads as U+FFFD.
    pub def scalars() -> Vec<i32> {
        let out = Vec<i32>.new(); var at = 0; let length = self.len() as i32;
        unsafe { while at < length { out.push(rt_string_scalar_at(self, at)); at += rt_string_scalar_width(self, at); } }
        out
    }

    pub def scalar_count() -> i32 {
        var count = 0; var at = 0; let length = self.len() as i32;
        unsafe { while at < length { count += 1; at += rt_string_scalar_width(self, at); } }
        count
    }

    // Extended grapheme clusters (user-perceived characters, Unicode UAX #29).
    pub def graphemes() -> Vec<String> {
        let out = Vec<String>.new(); var at = 0; let length = self.len() as i32;
        unsafe { while at < length { let end = rt_string_grapheme_end(self, at); out.push(self.substring(at, end - at)); at = end; } }
        out
    }

    pub def grapheme_count() -> i32 {
        var count = 0; var at = 0; let length = self.len() as i32;
        unsafe { while at < length { count += 1; at = rt_string_grapheme_end(self, at); } }
        count
    }

    pub def is_valid_utf8() -> Bool {
        unsafe { return rt_string_is_valid_utf8(self) != 0; }
    }

    // UTF-8 encoding of one scalar value; invalid values (surrogates, out of range) give U+FFFD.
    pub static def from_scalar(scalar: i32) -> String {
        unsafe { return String.from_handle(rt_string_from_scalar_handle(scalar)); }
    }

    pub def repeat(count: i32) -> String {
        unsafe { return String.from_handle(rt_string_repeat_handle(self, count)); }
    }

    pub def char_at(index: i32) -> i32 {
        unsafe { return rt_string_char_at(self, index); }
    }

    pub def byte_at(index: i32) -> i32 {
        unsafe { return rt_string_char_at(self, index); }
    }

    pub def find_char(ch: i32, start: i32) -> i32 {
        unsafe { return rt_string_find_char(self, ch, start); }
    }

    // Byte offsets, matching substring and byte_at; the result is a copy.
    pub def slice(bounds: IndexRange) -> String {
        let start = bounds.lower(self.len() as i32);
        let end = bounds.upper(self.len() as i32);
        if end <= start { return ""; }
        return self.substring(start, end - start);
    }

    pub def substring(start: i32, len: i32) -> String {
        unsafe { return String.from_handle(rt_string_substring_handle(self, start, len)); }
    }

    pub def trim() -> String {
        unsafe { return String.from_handle(rt_string_trim_handle(self)); }
    }

    pub def replace(old: String, new_val: String) -> String {
        unsafe { return String.from_handle(rt_string_replace_handle(self, old, new_val)); }
    }

    pub def to_i64() -> i64 {
        unsafe { return rt_string_to_i64(self); }
    }

    pub def to_i32() -> i32 {
        unsafe { return rt_string_to_i32(self); }
    }

    pub def to_f64() -> f64 {
        unsafe { return rt_string_to_f64(self); }
    }

    pub def find(needle: String) -> i32 {
        let n = needle.len() as i32;
        if n == 0 { return 0; }
        let max_idx = (self.len() as i32) - n;
        var i: i32 = 0;
        while i <= max_idx {
            let sub = self.substring(i, n);
            if sub.compare_to(needle) == 0 { return i; }
            i = i + 1;
        }
        return -1;
    }

    pub def count(needle: String) -> i32 {
        let n = needle.len() as i32;
        if n == 0 { return 0; }
        var count = 0;
        var pos: i32 = 0;
        let max_pos = (self.len() as i32) - n;
        while pos <= max_pos {
            let sub = self.substring(pos, n);
            if sub.compare_to(needle) == 0 {
                count = count + 1;
                pos = pos + n;
            } else {
                pos = pos + 1;
            }
        }
        return count;
    }

    pub def trim_start() -> String {
        var i: i32 = 0;
        let len = self.len() as i32;
        while i < len {
            let ch = self.char_at(i);
            if ch == 32 { } else if ch == 9 { } else if ch == 10 { } else if ch == 13 { } else { break; }
            i = i + 1;
        }
        return self.substring(i, len - i);
    }

    pub def trim_end() -> String {
        let len = self.len() as i32;
        var i = len - 1;
        while i >= 0 {
            let ch = self.char_at(i);
            if ch == 32 { } else if ch == 9 { } else if ch == 10 { } else if ch == 13 { } else { break; }
            i = i - 1;
        }
        return self.substring(0, i + 1);
    }

    pub def split(sep: String) -> Vec<String> {
        var out = Vec<String>.new();
        let n = sep.len() as i32;
        if n == 0 {
            out.push(self);
            return out;
        }

        var start = 0;
        var pos = 0;
        let total = self.len() as i32;
        while pos <= total - n {
            let sub = self.substring(pos, n);
            if sub.compare_to(sep) == 0 {
                out.push(self.substring(start, pos - start));
                pos = pos + n;
                start = pos;
            } else {
                pos = pos + 1;
            }
        }
        out.push(self.substring(start, total - start));
        return out;
    }

    pub def lines() -> Vec<String> {
        var out = Vec<String>.new();
        var start = 0;
        var i = 0;
        let total = self.len() as i32;
        while i < total {
            if self.char_at(i) == 10 {
                var end = i;
                if end > start {
                    if self.char_at(end - 1) == 13 { end = end - 1; }
                }
                out.push(self.substring(start, end - start));
                start = i + 1;
            }
            i = i + 1;
        }
        if start < total {
            var end = total;
            if end > start {
                if self.char_at(end - 1) == 13 { end = end - 1; }
            }
            out.push(self.substring(start, end - start));
        }
        return out;
    }
}

pub extension i32 {
    pub def to_string() -> String {
        unsafe { return String.from_handle(rt_int_to_string_handle(self as i64)); }
    }
}

pub extension i64 {
    pub def to_string() -> String {
        unsafe { return String.from_handle(rt_int_to_string_handle(self)); }
    }
}

pub extension f64 {
    pub def to_string() -> String {
        unsafe { return String.from_handle(rt_f64_to_string_handle(self)); }
    }
}

// Formatting uses the same ordinary to_string method for builtins and user types.
pub extension String {
    pub def to_string() -> String { return self; }
}
pub extension Bool {
    pub def to_string() -> String { if self { return "true"; } return "false"; }
}
pub extension i8 {
    pub def to_string() -> String { return (self as i64).to_string(); }
}
pub extension i16 {
    pub def to_string() -> String { return (self as i64).to_string(); }
}
pub extension u8 {
    pub def to_string() -> String { return (self as i64).to_string(); }
}
pub extension u16 {
    pub def to_string() -> String { return (self as i64).to_string(); }
}
pub extension u32 {
    pub def to_string() -> String { return (self as i64).to_string(); }
}
pub extension f32 {
    pub def to_string() -> String { return (self as f64).to_string(); }
}
pub extern "C" def rt_u64_to_string_handle(value: u64) -> RawPtr;
pub extension u64 {
    pub def to_string() -> String {
        unsafe { return String.from_handle(rt_u64_to_string_handle(self)); }
    }
}

// ---- Format specifications ----
//
// `{value:spec}` in an f-string calls value.format("spec"); types without a
// format method format their to_string(). A spec is
//   [[fill]align][sign][#][0][width][.precision][type]
// align: < left, > right, ^ center (numbers default right, text left);
// sign: + or space for non-negative numbers; # adds 0x/0o/0b; 0 pads numbers
// with zeros after the sign; precision: digits after the point for floats,
// maximum length for text; type: d x X o b for integers, f e % for numbers.
pub extern "C" def rt_f64_format_handle(value: f64, precision: i32, style: i32) -> RawPtr;

pub struct FormatSpec {
    pub var fill: String;
    pub var align: String;
    pub var sign: String;
    pub var alternate: Bool;
    pub var zero: Bool;
    pub var width: i32;
    pub var precision: i32;
    pub var kind: String;

    // nil when `spec` is not a valid specification.
    pub static def parse(spec: String) -> FormatSpec? {
        let format = FormatSpec { fill: " ", align: "", sign: "", alternate: false, zero: false, width: 0, precision: -1, kind: "" };
        let scalars = spec.scalars();
        let count = scalars.len();
        var at = 0;
        if count >= 2 && format_align(scalars[1]) {
            format.fill = String.from_scalar(scalars[0]); format.align = String.from_scalar(scalars[1]); at = 2;
        } else if count >= 1 && format_align(scalars[0]) {
            format.align = String.from_scalar(scalars[0]); at = 1;
        }
        if at < count && (scalars[at] == 43 || scalars[at] == 32) { format.sign = String.from_scalar(scalars[at]); at += 1; }
        if at < count && scalars[at] == 35 { format.alternate = true; at += 1; }
        if at < count && scalars[at] == 48 { format.zero = true; at += 1; }
        while at < count && format_digit(scalars[at]) {
            if format.width > 10000 { return nil; }
            format.width = format.width * 10 + scalars[at] - 48; at += 1;
        }
        if at < count && scalars[at] == 46 {
            at += 1;
            if at >= count || !format_digit(scalars[at]) { return nil; }
            format.precision = 0;
            while at < count && format_digit(scalars[at]) {
                if format.precision > 100 { return nil; }
                format.precision = format.precision * 10 + scalars[at] - 48; at += 1;
            }
        }
        if at < count {
            let kind = String.from_scalar(scalars[at]);
            if !"dxXobef%s".contains(kind) { return nil; }
            format.kind = kind; at += 1;
        }
        if at != count { return nil; }
        format
    }

    // Pads `prefix + body` to the width. Zero padding goes between a numeric
    // prefix (sign, 0x) and its digits.
    pub def pad(prefix: String, body: String, numeric: Bool) -> String {
        let length = prefix.scalar_count() + body.scalar_count();
        if length >= self.width { return prefix + body; }
        let missing = self.width - length;
        if self.zero && numeric && self.align.len() == 0 { return prefix + "0".repeat(missing) + body; }
        var align = self.align;
        if align.len() == 0 { align = numeric ? ">" : "<"; }
        if align.equals("<") { return prefix + body + self.fill.repeat(missing); }
        if align.equals(">") { return self.fill.repeat(missing) + prefix + body; }
        let left = missing / 2;
        self.fill.repeat(left) + prefix + body + self.fill.repeat(missing - left)
    }
    def sign_for(negative: Bool) -> String {
        if negative { return "-"; }
        self.sign
    }
}

def format_align(scalar: i32) -> Bool { scalar == 60 || scalar == 62 || scalar == 94 }
def format_digit(scalar: i32) -> Bool { scalar >= 48 && scalar <= 57 }

def format_magnitude(negative: Bool, magnitude: u64, spec: String) -> String {
    guard let format = FormatSpec.parse(spec) else { return magnitude.to_string(); }
    var base: u64 = 10;
    var prefix = "";
    var digits = "0123456789abcdef";
    if format.kind.equals("x") { base = 16; prefix = "0x"; }
    else if format.kind.equals("X") { base = 16; prefix = "0x"; digits = "0123456789ABCDEF"; }
    else if format.kind.equals("o") { base = 8; prefix = "0o"; }
    else if format.kind.equals("b") { base = 2; prefix = "0b"; }
    if !format.alternate { prefix = ""; }
    var text = "";
    var rest = magnitude;
    while true {
        let digit = (rest % base) as i32;
        text = digits.substring(digit, 1) + text;
        rest = rest / base;
        if rest == 0 { break; }
    }
    format.pad(format.sign_for(negative) + prefix, text, true)
}

def format_float_kind(spec: String) -> Bool {
    if let format = FormatSpec.parse(spec) { return format.kind.equals("e") || format.kind.equals("f") || format.kind.equals("%"); }
    false
}

pub extension i64 {
    pub def format(spec: String) -> String {
        if format_float_kind(spec) { return (self as f64).format(spec); }
        if self < 0 { return format_magnitude(true, (0 - self) as u64, spec); }
        format_magnitude(false, self as u64, spec)
    }
}
pub extension u64 {
    pub def format(spec: String) -> String {
        if format_float_kind(spec) { return (self as f64).format(spec); }
        format_magnitude(false, self, spec)
    }
}
pub extension i32 { pub def format(spec: String) -> String { (self as i64).format(spec) } }
pub extension i16 { pub def format(spec: String) -> String { (self as i64).format(spec) } }
pub extension i8 { pub def format(spec: String) -> String { (self as i64).format(spec) } }
pub extension u32 { pub def format(spec: String) -> String { (self as u64).format(spec) } }
pub extension u16 { pub def format(spec: String) -> String { (self as u64).format(spec) } }
pub extension u8 { pub def format(spec: String) -> String { (self as u64).format(spec) } }

pub extension f64 {
    pub def format(spec: String) -> String {
        guard let format = FormatSpec.parse(spec) else { return self.to_string(); }
        if format.kind.equals("d") || format.kind.equals("x") || format.kind.equals("X") || format.kind.equals("o") || format.kind.equals("b") {
            return (self as i64).format(spec);
        }
        let negative = self < 0.0;
        var magnitude = self; if negative { magnitude = 0.0 - self; }
        var precision = format.precision; if precision < 0 { precision = 6; }
        var body = "";
        unsafe {
            if format.kind.equals("e") { body = String.from_handle(rt_f64_format_handle(magnitude, precision, 101)); }
            else if format.kind.equals("%") { body = String.from_handle(rt_f64_format_handle(magnitude * 100.0, precision, 102)) + "%"; }
            else if format.kind.equals("f") || format.precision >= 0 { body = String.from_handle(rt_f64_format_handle(magnitude, precision, 102)); }
            else { body = magnitude.to_string(); }
        }
        format.pad(format.sign_for(negative), body, true)
    }
}
pub extension f32 { pub def format(spec: String) -> String { (self as f64).format(spec) } }

pub extension String {
    // Width and alignment; a precision keeps at most that many scalars.
    pub def format(spec: String) -> String {
        guard let format = FormatSpec.parse(spec) else { return self; }
        var text = self;
        if format.precision >= 0 && self.scalar_count() > format.precision {
            let scalars = self.scalars();
            text = "";
            for index in 0..<format.precision { text = text + String.from_scalar(scalars[index]); }
        }
        format.pad("", text, false)
    }
}
pub extension Bool { pub def format(spec: String) -> String { self.to_string().format(spec) } }
