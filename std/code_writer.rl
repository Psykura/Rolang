// Indented source output with explicit C byte-string escaping.
import "string.rl"
import "string_builder.rl"

// Returns a quoted C string literal. Fixed-width octal escapes preserve UTF-8
// bytes and NULs, and cannot consume following hexadecimal/digit characters.
pub def c_quote(text: String) -> String {
    let out = StringBuilder.new();
    out.append_byte(34 as u8);
    var i = 0;
    while (i as i64) < text.len() {
        let byte = text.byte_at(i);
        if byte == 34 || byte == 92 {
            out.append_byte(92 as u8);
            out.append_byte(byte as u8);
        } else {
            if byte < 32 || byte >= 127 || byte == 63 {
                out.append_byte(92 as u8);
                out.append_byte((48 + byte / 64) as u8);
                out.append_byte((48 + (byte / 8) % 8) as u8);
                out.append_byte((48 + byte % 8) as u8);
            } else { out.append_byte(byte as u8); }
        }
        i = i + 1;
    }
    out.append_byte(34 as u8);
    return out.to_string();
}

pub struct CodeWriter {
    var buffer: StringBuilder;
    var unit: String;
    var depth: i32;
    var line_start: Bool;

    pub static def new() -> CodeWriter { return CodeWriter.with_indent("    "); }
    pub static def with_indent(unit: String) -> CodeWriter {
        return CodeWriter { buffer: StringBuilder.new(), unit: unit, depth: 0, line_start: true };
    }
    pub def indent() -> Void { self.depth = self.depth + 1; }
    // Balanced callers can ignore the result; underflow leaves depth at zero.
    pub def dedent() -> Bool {
        if self.depth == 0 { return false; }
        self.depth = self.depth - 1;
        return true;
    }
    // Handles embedded newlines and consecutive writes on the same line.
    pub def write(text: String) -> Void {
        var start = 0;
        let length = text.len() as i32;
        while start < length {
            var end = text.find_char(10, start);
            if end < 0 { end = length; }
            if end > start {
                if self.line_start { self.buffer.append(self.unit.repeat(self.depth)); }
                self.buffer.append(text.substring(start, end - start));
                self.line_start = false;
            }
            if end < length {
                self.buffer.append_byte(10 as u8);
                self.line_start = true;
            }
            start = end + 1;
        }
    }
    pub def line(text: String) -> Void {
        self.write(text);
        self.buffer.append_byte(10 as u8);
        self.line_start = true;
    }
    pub def clear() -> Void {
        self.buffer.clear(); self.depth = 0; self.line_start = true;
    }
    pub def to_string() -> String { return self.buffer.to_string(); }
}
