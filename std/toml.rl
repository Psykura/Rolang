// Standard library: TOML 1.0 documents.
//
//     switch Toml.parse(text) {
//         case .ok(let config): let port = config["server"]["port"].as_int() ?? 8080;
//         case .err(let error): eprintln(error.to_string());
//     }
//     let text = Toml.encode(config);          // Result<String, TomlError>
//
// Documents load into Json values, the data model shared with std.json and
// Codable: tables are objects (in document order), arrays are arrays.
// Dates and times stay RFC 3339 text in strings, and are written back as
// TOML dates when they parse as such. TOML has no null, so encoding one fails.
import "string.rl"
import "vec.rl"
import "dict.rl"
import "range.rl"
import "result.rl"
import "string_builder.rl"
import "json.rl"

pub struct TomlError {
    pub let message: String;
    // 1-based position of the problem; 0 for encoding errors.
    pub let line: i32;
    pub let column: i32;
    pub def to_string() -> String {
        if self.line == 0 { return self.message; }
        f"{self.message} at line {self.line}, column {self.column}"
    }
}

pub struct Toml {
    pub static def parse(text: String) -> Result<Json, TomlError> {
        let parser = TomlParser { text, at: 0, length: text.len() as i32, root: Dict<String, Json>.new(),
            current: Dict<String, Json>.new(), current_path: "", kinds: Dict<String, String>.new(), failure: nil };
        parser.current = parser.root;
        if !text.is_valid_utf8() { parser.fail("invalid UTF-8"); } else { parser.document(); }
        if let problem = parser.failure { return Result<Json, TomlError>.err(error: problem); }
        Result<Json, TomlError>.ok(value: Json.object(parser.root))
    }

    // TOML text for an object; nested objects become [tables] and arrays of
    // objects [[tables]].
    pub static def encode(value: Json) -> Result<String, TomlError> {
        guard let root = value.as_object() else { return toml_encode_error("a TOML document must be an object"); }
        let out = StringBuilder.new();
        if let problem = toml_write_table(out, root, "") { return toml_encode_error(problem); }
        Result<String, TomlError>.ok(value: out.to_string())
    }
}

def toml_encode_error(message: String) -> Result<String, TomlError> {
    Result<String, TomlError>.err(error: TomlError { message, line: 0, column: 0 })
}

// ---- Encoding ----

def toml_is_table_array(value: Json) -> Bool {
    guard let items = value.as_array() else { return false; }
    if items.len() == 0 { return false; }
    for item in items { if let fields = item.as_object() {} else { return false; } }
    true
}

def toml_write_table(out: StringBuilder, table: Dict<String, Json>, path: String) -> String? {
    // Plain keys first, then sub-tables and arrays of tables, as TOML requires.
    for entry in table.entries() {
        if let fields = entry.value.as_object() { continue; }
        if toml_is_table_array(entry.value) { continue; }
        out.append(toml_key(entry.key) + " = ");
        if let problem = toml_write_value(out, entry.value) { return f"{problem} (key '{toml_dotted(path, toml_key(entry.key))}')"; }
        out.append("\n");
    }
    for entry in table.entries() {
        let child_path = toml_dotted(path, toml_key(entry.key));
        if let fields = entry.value.as_object() {
            if out.len() > 0 { out.append("\n"); }
            out.append("[" + child_path + "]\n");
            if let problem = toml_write_table(out, fields, child_path) { return problem; }
        } else if toml_is_table_array(entry.value) {
            for item in entry.value.as_array() ?? Vec<Json>.new() {
                if out.len() > 0 { out.append("\n"); }
                out.append("[[" + child_path + "]]\n");
                if let problem = toml_write_table(out, item.as_object() ?? Dict<String, Json>.new(), child_path) { return problem; }
            }
        }
    }
    nil
}

def toml_dotted(path: String, key: String) -> String {
    if path.len() == 0 { return key; }
    path + "." + key
}

// Table paths for bookkeeping: each key length-prefixed, so a key "b.c" and
// the path b.c differ.
def toml_join(path: String, key: String) -> String { path + f"{key.len()}:{key}/" }

// The dotted form of a bookkeeping path, for messages.
def toml_display(path: String) -> String {
    var out = "";
    var at = 0;
    let length = path.len() as i32;
    while at < length {
        let colon = path.find_char(58, at);
        if colon < 0 { break; }
        let size = path.substring(at, colon - at).to_i32();
        if out.len() > 0 { out += "."; }
        out += toml_key(path.substring(colon + 1, size));
        at = colon + 1 + size + 1;
    }
    out
}

// A TOML basic string, escaping control characters and DEL.
def toml_quote(text: String) -> String {
    let hex = "0123456789abcdef";
    let out = StringBuilder.new();
    out.append("\"");
    for index in 0..<(text.len() as i32) {
        let byte = text.byte_at(index);
        switch byte {
            case 34: out.append("\\\"");
            case 92: out.append("\\\\");
            case 10: out.append("\\n");
            case 13: out.append("\\r");
            case 9: out.append("\\t");
            default:
                if byte < 32 || byte == 127 { out.append("\\u00" + hex.substring(byte / 16, 1) + hex.substring(byte % 16, 1)); }
                else { out.append_byte(byte as u8); }
        }
    }
    out.append("\"");
    out.to_string()
}

def toml_key(key: String) -> String {
    if key.len() == 0 { return "\"\""; }
    for index in 0..<(key.len() as i32) {
        let byte = key.byte_at(index);
        let bare = (byte >= 97 && byte <= 122) || (byte >= 65 && byte <= 90) || (byte >= 48 && byte <= 57) || byte == 95 || byte == 45;
        if !bare { return toml_quote(key); }
    }
    key
}

def toml_write_value(out: StringBuilder, value: Json) -> String? {
    switch value {
        case .null: return "TOML has no null value";
        case .bool(let flag): if flag { out.append("true"); } else { out.append("false"); }
        case .int(let number): out.append(number.to_string());
        case .float(let number):
            if number != number { out.append("nan"); }
            else if number - number != 0.0 { if number > 0.0 { out.append("inf"); } else { out.append("-inf"); } }
            else {
                let text = number.to_string();
                out.append(text);
                if text.find(".") < 0 && text.find("e") < 0 { out.append(".0"); }
            }
        case .string(let text):
            // RFC 3339 text written back as a TOML date or time.
            if toml_datetime_text(text) { out.append(text); } else { out.append(toml_quote(text)); }
        case .array(let items):
            out.append("[");
            for index in 0..<items.len() {
                if index > 0 { out.append(", "); }
                if let problem = toml_write_value(out, items[index]) { return problem; }
            }
            out.append("]");
        case .object(let fields):
            out.append("{");
            var first = true;
            for entry in fields.entries() {
                if !first { out.append(", "); }
                first = false;
                out.append(toml_key(entry.key) + " = ");
                if let problem = toml_write_value(out, entry.value) { return problem; }
            }
            out.append("}");
    }
    nil
}

// Whether `text` is a TOML date, time or date-time such as 1979-05-27,
// 07:32:00 or 1979-05-27T07:32:00Z.
def toml_datetime_text(text: String) -> Bool {
    let parser = TomlParser { text, at: 0, length: text.len() as i32, root: Dict<String, Json>.new(),
        current: Dict<String, Json>.new(), current_path: "", kinds: Dict<String, String>.new(), failure: nil };
    if let value = parser.datetime() { return parser.at == parser.length && parser.failure == nil; }
    false
}

// ---- Parsing ----

struct TomlParser {
    let text: String;
    var at: i32;
    let length: i32;
    let root: Dict<String, Json>;
    var current: Dict<String, Json>;
    var current_path: String;
    // Table paths: "header" from [a.b], "implicit" from a parent header,
    // "dotted" from dotted keys, "inline" for inline tables, "array" for [[a]].
    let kinds: Dict<String, String>;
    var failure: TomlError?;

    def byte() -> i32 { if self.at < self.length { return self.text.byte_at(self.at); } -1 }
    def peek(offset: i32) -> i32 { if self.at + offset < self.length { return self.text.byte_at(self.at + offset); } -1 }
    def fail(message: String) -> Void {
        if self.failure != nil { return; }
        var line = 1; var column = 1;
        for index in 0..<self.at {
            let byte = self.text.byte_at(index);
            if byte == 10 { line += 1; column = 1; } else if byte < 128 || byte >= 192 { column += 1; }
        }
        self.failure = TomlError { message, line, column };
    }
    def failed() -> Bool { self.failure != nil }
    def skip_blanks() -> Void { while self.byte() == 32 || self.byte() == 9 { self.at += 1; } }
    def skip_comment() -> Void {
        if self.byte() != 35 { return; }
        while self.at < self.length && self.byte() != 10 {
            let byte = self.byte();
            if byte == 13 && self.peek(1) == 10 { return; }
            if (byte < 32 && byte != 9) || byte == 127 { self.fail("control character in comment"); return; }
            self.at += 1;
        }
    }
    // Blank space, comments and newlines, as allowed between array elements.
    def skip_space_and_newlines() -> Void {
        while true {
            self.skip_blanks();
            self.skip_comment();
            if self.byte() == 10 { self.at += 1; continue; }
            if self.byte() == 13 && self.peek(1) == 10 { self.at += 2; continue; }
            return;
        }
    }
    // The rest of the line must be blank or a comment.
    def end_of_line() -> Void {
        self.skip_blanks();
        self.skip_comment();
        if self.at >= self.length { return; }
        if self.byte() == 10 { self.at += 1; return; }
        if self.byte() == 13 && self.peek(1) == 10 { self.at += 2; return; }
        self.fail("expected the end of the line");
    }

    def document() -> Void {
        while self.at < self.length && !self.failed() {
            self.skip_space_and_newlines();
            if self.at >= self.length { return; }
            if self.byte() == 91 { self.table_header(); }
            else { self.key_value(self.current, self.current_path); }
            if self.failed() { return; }
            self.end_of_line();
        }
    }

    def table_header() -> Void {
        self.at += 1;
        let array = self.byte() == 91;
        if array { self.at += 1; }
        self.skip_blanks();
        guard let keys = self.key() else { return; }
        self.skip_blanks();
        if self.byte() != 93 { self.fail("expected ']' after table name"); return; }
        self.at += 1;
        if array { if self.byte() != 93 { self.fail("expected ']]' after array of tables name"); return; } self.at += 1; }
        // Parent tables are created implicitly.
        var table = self.root; var path = "";
        for index in 0..<(keys.len() - 1) {
            path = toml_join(path, keys[index]);
            guard let next = self.descend(table, keys[index], path, "implicit") else { return; }
            table = next;
        }
        let last = keys[keys.len() - 1];
        path = toml_join(path, last);
        let kind = self.kinds[path] ?? "";
        if array {
            if kind.len() > 0 && !kind.equals("array") { self.fail(f"cannot define '{toml_display(path)}' as an array of tables; it is already a table"); return; }
            if let existing = table[last] {
                if kind.len() == 0 { self.fail(f"key '{toml_display(path)}' is already defined"); return; }
            } else { table[last] = Json.array(Vec<Json>.new()); }
            let fresh = Dict<String, Json>.new();
            if let items = table[last]?.as_array() { items.push(Json.object(fresh)); }
            self.kinds[path] = "array";
            // A new element: forget the previous element's sub-tables.
            let stale = Vec<String>.new();
            for entry in self.kinds.entries() { if entry.key.starts_with(path) && !entry.key.equals(path) { stale.push(entry.key); } }
            for key in stale { self.kinds.remove(key); }
            self.current = fresh; self.current_path = path;
            return;
        }
        if kind.equals("header") || kind.equals("dotted") || kind.equals("inline") || kind.equals("array") {
            self.fail(f"table '{toml_display(path)}' is already defined"); return;
        }
        if let existing = table[last] {
            guard let fields = existing.as_object() else { self.fail(f"key '{toml_display(path)}' is already defined"); return; }
            self.current = fields;
        } else {
            let fresh = Dict<String, Json>.new();
            table[last] = Json.object(fresh);
            self.current = fresh;
        }
        self.kinds[path] = "header";
        self.current_path = path;
    }

    // The table `key` of `table`, created as `kind` when missing; for an array
    // of tables, its last element.
    def descend(table: Dict<String, Json>, key: String, path: String, kind: String) -> Dict<String, Json>? {
        if let existing = table[key] {
            let known = self.kinds[path] ?? "";
            if known.equals("inline") { self.fail(f"inline table '{toml_display(path)}' cannot be extended"); return nil; }
            if kind.equals("dotted") && (known.equals("header") || known.equals("array")) { self.fail(f"table '{toml_display(path)}' is already defined"); return nil; }
            if let fields = existing.as_object() { return fields; }
            if known.equals("array") { if let items = existing.as_array() { if let last = items[items.len() - 1].as_object() { return last; } } }
            self.fail(f"key '{toml_display(path)}' is already defined as a value");
            return nil;
        }
        let fresh = Dict<String, Json>.new();
        table[key] = Json.object(fresh);
        self.kinds[path] = kind;
        fresh
    }

    def key_value(table: Dict<String, Json>, path: String) -> Void {
        guard let keys = self.key() else { return; }
        self.skip_blanks();
        if self.byte() != 61 { self.fail("expected '=' after key"); return; }
        self.at += 1;
        self.skip_blanks();
        var target = table; var target_path = path;
        for index in 0..<(keys.len() - 1) {
            target_path = toml_join(target_path, keys[index]);
            guard let next = self.descend(target, keys[index], target_path, "dotted") else { return; }
            target = next;
        }
        let last = keys[keys.len() - 1];
        let full = toml_join(target_path, last);
        if target.contains(last) { self.fail(f"key '{toml_display(full)}' is already defined"); return; }
        guard let value = self.value(full) else { return; }
        target[last] = value;
    }

    // A dotted key: bare, "basic" or 'literal' parts separated by dots.
    def key() -> Vec<String>? {
        let parts = Vec<String>.new();
        while true {
            self.skip_blanks();
            let byte = self.byte();
            if byte == 34 || byte == 39 {
                if (byte == 34 && self.peek(1) == 34 && self.peek(2) == 34) || (byte == 39 && self.peek(1) == 39 && self.peek(2) == 39) {
                    self.fail("multi-line strings cannot be keys"); return nil;
                }
                guard let text = self.string_value() else { return nil; }
                parts.push(text);
            } else {
                let start = self.at;
                while true {
                    let c = self.byte();
                    if (c >= 97 && c <= 122) || (c >= 65 && c <= 90) || (c >= 48 && c <= 57) || c == 95 || c == 45 { self.at += 1; } else { break; }
                }
                if self.at == start { self.fail("expected a key"); return nil; }
                parts.push(self.text.substring(start, self.at - start));
            }
            self.skip_blanks();
            if self.byte() != 46 { break; }
            self.at += 1;
        }
        parts
    }

    def value(path: String) -> Json? {
        let byte = self.byte();
        if byte == 34 || byte == 39 { if let text = self.string_value() { return Json.string(text); } return nil; }
        if byte == 91 { return self.array(path); }
        if byte == 123 { return self.inline_table(path); }
        if self.word("true") { return Json.bool(true); }
        if self.word("false") { return Json.bool(false); }
        if let date = self.datetime() { return Json.string(date); }
        if self.failed() { return nil; }
        self.number()
    }
    def word(expected: String) -> Bool {
        let size = expected.len() as i32;
        if self.at + size > self.length || !self.text.substring(self.at, size).equals(expected) { return false; }
        let after = self.peek(size);
        if (after >= 97 && after <= 122) || (after >= 48 && after <= 57) || after == 95 || after == 45 { return false; }
        self.at += size;
        true
    }

    def array(path: String) -> Json? {
        self.at += 1;
        let items = Vec<Json>.new();
        while true {
            self.skip_space_and_newlines();
            if self.failed() { return nil; }
            if self.byte() == 93 { self.at += 1; break; }
            if self.at >= self.length { self.fail("unterminated array"); return nil; }
            guard let item = self.value(path) else { return nil; }
            items.push(item);
            self.skip_space_and_newlines();
            if self.byte() == 44 { self.at += 1; continue; }
            if self.byte() == 93 { self.at += 1; break; }
            self.fail("expected ',' or ']' in array"); return nil;
        }
        Json.array(items)
    }

    def inline_table(path: String) -> Json? {
        self.at += 1;
        let fields = Dict<String, Json>.new();
        self.kinds[path] = "inline";
        self.skip_blanks();
        if self.byte() == 125 { self.at += 1; return Json.object(fields); }
        while true {
            self.skip_blanks();
            self.key_value(fields, path);
            if self.failed() { return nil; }
            self.skip_blanks();
            if self.byte() == 44 { self.at += 1; continue; }
            if self.byte() == 125 { self.at += 1; break; }
            self.fail("expected ',' or '}' in inline table"); return nil;
        }
        // Tables created by dotted keys inside are part of the inline table.
        for entry in self.kinds.entries() { if entry.key.starts_with(path) && !entry.key.equals(path) { self.kinds[entry.key] = "inline"; } }
        Json.object(fields)
    }

    def string_value() -> String? {
        let quote = self.byte();
        let multi = self.peek(1) == quote && self.peek(2) == quote;
        if multi { self.at += 3; } else { self.at += 1; }
        // A newline right after the opening delimiter is trimmed.
        if multi {
            if self.byte() == 10 { self.at += 1; }
            else if self.byte() == 13 && self.peek(1) == 10 { self.at += 2; }
        }
        let out = StringBuilder.new();
        while true {
            if self.at >= self.length { self.fail("unterminated string"); return nil; }
            let byte = self.byte();
            if byte == quote {
                if !multi { self.at += 1; break; }
                if self.peek(1) == quote && self.peek(2) == quote {
                    // Up to two quotes may end the content: """a"""" is a".
                    var extra = 0;
                    while extra < 2 && self.peek(3 + extra) == quote { extra += 1; }
                    for index in 0..<extra { out.append_byte(quote as u8); }
                    self.at += 3 + extra;
                    break;
                }
                out.append_byte(byte as u8); self.at += 1; continue;
            }
            if byte == 10 && !multi { self.fail("newline in single-line string"); return nil; }
            if byte == 13 {
                if multi && self.peek(1) == 10 { out.append("\n"); self.at += 2; continue; }
                self.fail("bare carriage return in string"); return nil;
            }
            if (byte < 32 && byte != 9 && byte != 10) || byte == 127 { self.fail("control character in string"); return nil; }
            if byte == 92 && quote == 34 {
                self.at += 1;
                let escape = self.byte();
                self.at += 1;
                switch escape {
                    case 98: out.append_byte(8 as u8);
                    case 116: out.append("\t");
                    case 110: out.append("\n");
                    case 102: out.append_byte(12 as u8);
                    case 114: out.append("\r");
                    case 101: out.append_byte(27 as u8);
                    case 34: out.append("\"");
                    case 92: out.append("\\");
                    case 117, 85:
                        var digits = 4; if escape == 85 { digits = 8; }
                        guard let scalar = self.hex(digits) else { self.fail("invalid unicode escape"); return nil; }
                        if (scalar >= 55296 && scalar <= 57343) || scalar > 1114111 { self.fail("unicode escape is not a scalar value"); return nil; }
                        out.append(String.from_scalar(scalar));
                    default:
                        // A backslash ending a line in a multi-line string trims the newline and following space.
                        if multi && (escape == 32 || escape == 9 || escape == 10 || escape == 13) {
                            self.at -= 1;
                            self.skip_blanks();
                            if self.byte() != 10 && !(self.byte() == 13 && self.peek(1) == 10) { self.fail("invalid escape in string"); return nil; }
                            while self.byte() == 32 || self.byte() == 9 || self.byte() == 10 || (self.byte() == 13 && self.peek(1) == 10) { self.at += 1; }
                        } else { self.at -= 1; self.fail("invalid escape in string"); return nil; }
                }
                continue;
            }
            out.append_byte(byte as u8);
            self.at += 1;
        }
        out.to_string()
    }
    def hex(digits: i32) -> i32? {
        if self.at + digits > self.length { return nil; }
        var value = 0;
        for index in 0..<digits {
            let byte = self.text.byte_at(self.at + index);
            var digit = -1;
            if byte >= 48 && byte <= 57 { digit = byte - 48; }
            else if byte >= 97 && byte <= 102 { digit = byte - 87; }
            else if byte >= 65 && byte <= 70 { digit = byte - 55; }
            if digit < 0 { return nil; }
            if value > 16777215 { return nil; }
            value = value * 16 + digit;
        }
        self.at += digits;
        value
    }

    // Numbers: decimal, 0x/0o/0b integers, floats, inf and nan, with
    // underscores between digits.
    def number() -> Json? {
        let start = self.at;
        var sign = "";
        if self.byte() == 43 || self.byte() == 45 { sign = self.text.substring(self.at, 1); self.at += 1; }
        if self.word("inf") { if sign.equals("-") { return Json.float(-1.0 / 0.0); } return Json.float(1.0 / 0.0); }
        if self.word("nan") { return Json.float(0.0 / 0.0); }
        if self.byte() == 48 && (self.peek(1) == 120 || self.peek(1) == 111 || self.peek(1) == 98) {
            if sign.len() > 0 { self.fail("prefixed integers cannot have a sign"); return nil; }
            var base: i64 = 16; if self.peek(1) == 111 { base = 8; } if self.peek(1) == 98 { base = 2; }
            self.at += 2;
            guard let digits = self.digits(base) else { return nil; }
            var value: i64 = 0;
            for index in 0..<(digits.len() as i32) {
                let byte = digits.byte_at(index);
                var digit = (byte - 48) as i64;
                if byte >= 97 { digit = (byte - 87) as i64; } else if byte >= 65 { digit = (byte - 55) as i64; }
                if value > (9223372036854775807 - digit) / base { self.fail("integer out of range"); return nil; }
                value = value * base + digit;
            }
            return Json.int(value);
        }
        guard let whole = self.digits(10) else { return nil; }
        if whole.len() > 1 && whole.starts_with("0") { self.fail("leading zeros are not allowed"); return nil; }
        var float = false;
        var text = sign + whole;
        if self.byte() == 46 {
            self.at += 1; float = true;
            guard let fraction = self.digits(10) else { return nil; }
            text += "." + fraction;
        }
        if self.byte() == 101 || self.byte() == 69 {
            self.at += 1; float = true;
            var exponent_sign = "";
            if self.byte() == 43 || self.byte() == 45 { exponent_sign = self.text.substring(self.at, 1); self.at += 1; }
            guard let exponent = self.digits(10) else { return nil; }
            text += "e" + exponent_sign + exponent;
        }
        if float { return Json.float(text.to_f64()); }
        let magnitude = whole;
        var limit = "9223372036854775807"; if sign.equals("-") { limit = "9223372036854775808"; }
        if magnitude.len() > 19 || (magnitude.len() == 19 && magnitude > limit) { self.at = start; self.fail("integer out of range"); return nil; }
        Json.int(text.to_i64())
    }
    // Digits of `base` with single underscores between them, without the underscores.
    def digits(base: i64) -> String? {
        let start = self.at;
        let out = StringBuilder.new();
        var previous_digit = false;
        while true {
            let byte = self.byte();
            var digit = false;
            if base == 10 || base == 16 { digit = byte >= 48 && byte <= 57; }
            if base == 8 { digit = byte >= 48 && byte <= 55; }
            if base == 2 { digit = byte == 48 || byte == 49; }
            if base == 16 && ((byte >= 97 && byte <= 102) || (byte >= 65 && byte <= 70)) { digit = true; }
            if digit { out.append_byte(byte as u8); self.at += 1; previous_digit = true; continue; }
            if byte == 95 && previous_digit {
                let next = self.peek(1);
                var next_digit = next >= 48 && next <= 57;
                if base == 16 && ((next >= 97 && next <= 102) || (next >= 65 && next <= 70)) { next_digit = true; }
                if !next_digit { self.fail("an underscore must be between digits"); return nil; }
                self.at += 1; previous_digit = false; continue;
            }
            break;
        }
        if out.len() == 0 { self.at = start; self.fail("expected a value"); return nil; }
        out.to_string()
    }

    // A date, time or date-time, normalized to RFC 3339 text: 1979-05-27,
    // 07:32:00, 1979-05-27T07:32:00Z. nil without consuming anything when the
    // text is not one.
    def datetime() -> String? {
        let start = self.at;
        var text = "";
        if self.is_digit(0) && self.is_digit(1) && self.is_digit(2) && self.is_digit(3) && self.peek(4) == 45 {
            guard let date = self.date() else { return nil; }
            text = date;
            var separator = self.byte();
            if separator == 32 && !self.is_digit(1) { return text; }
            if separator == 84 || separator == 116 || separator == 32 {
                self.at += 1;
                guard let time = self.time() else { return nil; }
                text += "T" + time;
                if self.byte() == 90 || self.byte() == 122 { self.at += 1; text += "Z"; }
                else if self.byte() == 43 || self.byte() == 45 {
                    let sign = self.text.substring(self.at, 1);
                    self.at += 1;
                    guard let hours = self.two_digits(23) else { return nil; }
                    if self.byte() != 58 { self.fail("invalid time offset"); return nil; }
                    self.at += 1;
                    guard let minutes = self.two_digits(59) else { return nil; }
                    text += f"{sign}{hours:02}:{minutes:02}";
                }
            }
            return text;
        }
        if self.is_digit(0) && self.is_digit(1) && self.peek(2) == 58 {
            guard let time = self.time() else { return nil; }
            return time;
        }
        self.at = start;
        nil
    }
    def is_digit(offset: i32) -> Bool { let byte = self.peek(offset); byte >= 48 && byte <= 57 }
    def two_digits(maximum: i32) -> i32? {
        if !self.is_digit(0) || !self.is_digit(1) { self.fail("invalid date or time"); return nil; }
        let value = (self.byte() - 48) * 10 + self.peek(1) - 48;
        if value > maximum { self.fail("invalid date or time"); return nil; }
        self.at += 2;
        value
    }
    def date() -> String? {
        var year = 0;
        for index in 0..<4 { year = year * 10 + self.peek(index) - 48; }
        self.at += 5;
        guard let month = self.two_digits(12) else { return nil; }
        if self.byte() != 45 { self.fail("invalid date"); return nil; }
        self.at += 1;
        guard let day = self.two_digits(31) else { return nil; }
        if month == 0 || day == 0 { self.fail("invalid date"); return nil; }
        var days = 31;
        if month == 4 || month == 6 || month == 9 || month == 11 { days = 30; }
        if month == 2 { days = 28; if (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 { days = 29; } }
        if day > days { self.fail("invalid date"); return nil; }
        f"{year:04}-{month:02}-{day:02}"
    }
    def time() -> String? {
        guard let hour = self.two_digits(23) else { return nil; }
        if self.byte() != 58 { self.fail("invalid time"); return nil; }
        self.at += 1;
        guard let minute = self.two_digits(59) else { return nil; }
        if self.byte() != 58 { self.fail("invalid time"); return nil; }
        self.at += 1;
        guard let second = self.two_digits(60) else { return nil; }
        var text = f"{hour:02}:{minute:02}:{second:02}";
        if self.byte() == 46 {
            self.at += 1;
            let start = self.at;
            while self.is_digit(0) { self.at += 1; }
            if self.at == start { self.fail("invalid fractional seconds"); return nil; }
            text += "." + self.text.substring(start, self.at - start);
        }
        text
    }
}
