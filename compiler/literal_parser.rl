// Literal token conversion shared by pattern and expression parsing.
pub import "lexer.rl"
pub import "ast.rl"
import std.string_builder

def digit_value(byte: i32) -> i32 {
    if byte >= 48 && byte <= 57 { return byte - 48; }
    if byte >= 65 && byte <= 70 { return byte - 65 + 10; }
    if byte >= 97 && byte <= 102 { return byte - 97 + 10; }
    -1
}

// Build integer literal decimal text without narrowing to i64.
def decimal_integer(spelling: String) -> String {
    var base = 10;
    var start = 0;
    if spelling.len() >= 2 && spelling.byte_at(0) == 48 {
        let prefix = spelling.byte_at(1);
        if prefix == 120 || prefix == 88 { base = 16; start = 2; }
        if prefix == 98 || prefix == 66 { base = 2; start = 2; }
        if prefix == 111 || prefix == 79 { base = 8; start = 2; }
    }
    let digits = Vec<i32>.new();
    digits.push(0);
    for index in start..<(spelling.len() as i32) {
        let byte = spelling.byte_at(index);
        if byte == 95 { continue; }
        var carry = digit_value(byte);
        var place = 0;
        while place < digits.len() {
            let value = digits[place] * base + carry;
            digits[place] = value % 10;
            carry = value / 10;
            place += 1;
        }
        while carry > 0 {
            digits.push(carry % 10);
            carry /= 10;
        }
    }
    let result = StringBuilder.new();
    var index = digits.len() - 1;
    while index >= 0 {
        result.append_byte((digits[index] + 48) as u8);
        index -= 1;
    }
    result.to_string()
}

pub def unescape_literal(source: String) -> String {
    let result = StringBuilder.new();
    var index = 0;
    while index < source.len() {
        let byte = source.byte_at(index);
        if byte == 92 && index + 1 < source.len() {
            let next = source.byte_at(index + 1);
            if next == 117 { if let after = append_unicode_escape(source, index, result) { index = after; continue; } }
            switch next {
                case 110: result.append_byte(10 as u8);
                case 116: result.append_byte(9 as u8);
                case 114: result.append_byte(13 as u8);
                case 48: result.append_byte(0 as u8);
                default: result.append_byte(next as u8);
            }
            index += 2;
        } else {
            result.append_byte(byte as u8);
            index += 1;
        }
    }
    result.to_string()
}

// `\u{1F600}` at `index`: appends the scalar's UTF-8 bytes and returns the index after
// `}`, or nil when the escape is malformed (it is then kept as written).
def append_unicode_escape(source: String, index: i32, result: StringBuilder) -> i32? {
    let length = source.len() as i32;
    if index + 2 >= length || source.byte_at(index + 2) != 123 { return nil; }
    var at = index + 3; var value = 0; var digits = 0;
    while at < length && source.byte_at(at) != 125 {
        let c = source.byte_at(at); var digit = -1;
        if c >= 48 && c <= 57 { digit = c - 48; } else if c >= 97 && c <= 102 { digit = c - 87; } else if c >= 65 && c <= 70 { digit = c - 55; }
        if digit < 0 || digits >= 6 { return nil; }
        value = value * 16 + digit; digits += 1; at += 1;
    }
    if at >= length || digits == 0 || value > 1114111 || (value >= 55296 && value <= 57343) { return nil; }
    if value < 128 { result.append_byte(value as u8); }
    else if value < 2048 { result.append_byte((192 | (value >> 6)) as u8); result.append_byte((128 | (value & 63)) as u8); }
    else if value < 65536 { result.append_byte((224 | (value >> 12)) as u8); result.append_byte((128 | ((value >> 6) & 63)) as u8); result.append_byte((128 | (value & 63)) as u8); }
    else { result.append_byte((240 | (value >> 18)) as u8); result.append_byte((128 | ((value >> 12) & 63)) as u8); result.append_byte((128 | ((value >> 6) & 63)) as u8); result.append_byte((128 | (value & 63)) as u8); }
    at + 1
}

def first_codepoint(value: String) -> i32 {
    let first = value.byte_at(0);
    if first < 128 { return first; }
    if first < 224 { return ((first & 31) << 6) | (value.byte_at(1) & 63); }
    if first < 240 {
        return ((first & 15) << 12) | ((value.byte_at(1) & 63) << 6) | (value.byte_at(2) & 63);
    }
    ((first & 7) << 18) | ((value.byte_at(1) & 63) << 12) |
        ((value.byte_at(2) & 63) << 6) | (value.byte_at(3) & 63)
}

pub def literal_form(token: LexToken) -> NodeForm? {
    let raw = token.text;
    switch token.kind {
        case .integer:
            return NodeForm.literal(LiteralAst { value: LiteralValue.integer(decimal_integer(raw)), kind: "int" });
        case .floating:
            return NodeForm.literal(LiteralAst { value: LiteralValue.floating(raw.replace("_", "").to_f64()), kind: "float" });
        case .string:
            return NodeForm.literal(LiteralAst { value: LiteralValue.text(unescape_literal(raw.substring(1, (raw.len() as i32) - 2))), kind: "string" });
        case .raw_string:
            var prefix = 2;
            var ending = 1;
            if raw.starts_with("r\"\"\"") { prefix = 4; ending = 3; }
            else if raw.starts_with("r#") {
                // r#"..."#: the opening and closing quotes carry the same `#`s.
                var hashes = 0;
                while raw.byte_at(1 + hashes) == 35 { hashes += 1; }
                prefix = 2 + hashes; ending = 1 + hashes;
            }
            return NodeForm.literal(LiteralAst { value: LiteralValue.text(raw.substring(prefix, (raw.len() as i32) - prefix - ending)), kind: "string" });
        case .multiline_string:
            return NodeForm.literal(LiteralAst { value: LiteralValue.text(unescape_literal(raw.substring(3, (raw.len() as i32) - 6))), kind: "string" });
        case .character:
            let value = unescape_literal(raw.substring(1, (raw.len() as i32) - 2));
            return NodeForm.literal(LiteralAst { value: LiteralValue.integer(first_codepoint(value).to_string()), kind: "char" });
        case .identifier:
            if raw.equals("true") { return NodeForm.literal(LiteralAst { value: LiteralValue.boolean(true), kind: "bool" }); }
            if raw.equals("false") { return NodeForm.literal(LiteralAst { value: LiteralValue.boolean(false), kind: "bool" }); }
            if raw.equals("nil") { return NodeForm.literal(LiteralAst { value: LiteralValue.none(), kind: "nil" }); }
        default: {}
    }
    nil
}
