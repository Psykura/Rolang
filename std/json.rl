// Standard library: JSON values, parsing and serialization (RFC 8259).
//
//     switch Json.parse(text) {
//         case .ok(let doc):
//             let name = doc["user"]["name"].as_string() ?? "anonymous";
//             let tags = doc["tags"].as_array() ?? Vec<Json>.new();
//         case .err(let error): eprintln(error.to_string());
//     }
//     let reply = Json.empty_object();
//     reply.set("ok", Json.bool(true));
//     reply.set("count", Json.int(3));
//     println(reply.to_string());              // {"ok":true,"count":3}
//
// Integers that fit in i64 stay exact as `int`; other numbers are `float`.
// Objects keep their key order; a repeated key keeps its last value.
import "string.rl"
import "vec.rl"
import "dict.rl"
import "range.rl"
import "result.rl"
import "string_builder.rl"

pub enum Json {
    case null;
    case bool(Bool);
    case int(i64);
    case float(f64);
    case string(String);
    case array(Vec<Json>);
    case object(Dict<String, Json>);

    pub static def parse(text: String) -> Result<Json, JsonError> {
        let parser = JsonParser { text, at: 0, length: text.len() as i32, depth: 0 };
        parser.skip_space();
        let value = parser.value();
        switch value {
            case .ok(let json):
                parser.skip_space();
                if parser.at < parser.length { return parser.fail("unexpected text after the JSON value"); }
                return value;
            default: return value;
        }
    }
    // An empty object or array to fill with set/push.
    pub static def empty_object() -> Json { Json.object(Dict<String, Json>.new()) }
    pub static def empty_array() -> Json { Json.array(Vec<Json>.new()) }

    // The member `key` of an object, or nil.
    pub def get(key: String) -> Json? {
        switch self { case .object(let fields): return fields[key]; default: return nil; }
    }
    // The element at `index` of an array, or nil.
    pub def at(index: i32) -> Json? {
        switch self {
            case .array(let items): if index >= 0 && index < items.len() { return items[index]; } return nil;
            default: return nil;
        }
    }
    // `json["a"]["b"]`: null when a member is missing, so lookups chain.
    pub def __get__(key: String) -> Json { self.get(key) ?? Json.null() }
    // Sets a member of an object; ignored for other values.
    pub def set(key: String, value: Json) -> Void {
        switch self { case .object(let fields): fields[key] = value; default: {} }
    }
    // Appends to an array; ignored for other values.
    pub def push(value: Json) -> Void {
        switch self { case .array(let items): items.push(value); default: {} }
    }
    // Members of an object or elements of an array; 0 otherwise.
    pub def len() -> i32 {
        switch self {
            case .array(let items): return items.len();
            case .object(let fields): return fields.len() as i32;
            default: return 0;
        }
    }

    pub def is_null() -> Bool { switch self { case .null: return true; default: return false; } }
    pub def as_bool() -> Bool? { switch self { case .bool(let value): return value; default: return nil; } }
    pub def as_int() -> i64? { switch self { case .int(let value): return value; default: return nil; } }
    // Integers convert to f64.
    pub def as_f64() -> f64? {
        switch self {
            case .int(let value): return value as f64;
            case .float(let value): return value;
            default: return nil;
        }
    }
    pub def as_string() -> String? { switch self { case .string(let value): return value; default: return nil; } }
    pub def as_array() -> Vec<Json>? { switch self { case .array(let items): return items; default: return nil; } }
    pub def as_object() -> Dict<String, Json>? { switch self { case .object(let fields): return fields; default: return nil; } }

    // Structural equality; an int and a float are equal when their values are.
    pub def __eq__(other: Json) -> Bool {
        switch self {
            case .null: return other.is_null();
            case .bool(let value): if let theirs = other.as_bool() { return value == theirs; } return false;
            case .int(let value):
                if let theirs = other.as_int() { return value == theirs; }
                if let theirs = other.as_f64() { return (value as f64) == theirs; }
                return false;
            case .float(let value): if let theirs = other.as_f64() { return value == theirs; } return false;
            case .string(let value): if let theirs = other.as_string() { return value.equals(theirs); } return false;
            case .array(let items):
                guard let theirs = other.as_array() else { return false; }
                if items.len() != theirs.len() { return false; }
                for index in 0..<items.len() { if !(items[index] == theirs[index]) { return false; } }
                return true;
            case .object(let fields):
                guard let theirs = other.as_object() else { return false; }
                if fields.len() != theirs.len() { return false; }
                for entry in fields.entries() {
                    guard let value = theirs[entry.key] else { return false; }
                    if !(entry.value == value) { return false; }
                }
                return true;
        }
    }
    pub def __ne__(other: Json) -> Bool { !(self == other) }

    // Compact JSON text.
    pub def to_string() -> String {
        let out = StringBuilder.new();
        json_write(out, self, -1, 0);
        out.to_string()
    }
    // Indented JSON text, `indent` spaces per level.
    pub def pretty(indent: i32 = 2) -> String {
        let out = StringBuilder.new();
        json_write(out, self, indent, 0);
        out.to_string()
    }
}

pub struct JsonError {
    pub let message: String;
    // 1-based position of the problem.
    pub let line: i32;
    pub let column: i32;
    pub def to_string() -> String { f"{self.message} at line {self.line}, column {self.column}" }
}

// JSON string syntax for `text`, with quotes.
pub def json_quote(text: String) -> String {
    let out = StringBuilder.new();
    json_write_string(out, text);
    out.to_string()
}

def json_write(out: StringBuilder, value: Json, indent: i32, level: i32) -> Void {
    switch value {
        case .null: out.append("null");
        case .bool(let flag): if flag { out.append("true"); } else { out.append("false"); }
        case .int(let number): out.append(number.to_string());
        case .float(let number):
            // JSON has no NaN or infinity.
            if number != number || number - number != 0.0 { out.append("null"); return; }
            let text = number.to_string();
            out.append(text);
            // Keep a float a float when the text is read back.
            if text.find(".") < 0 && text.find("e") < 0 { out.append(".0"); }
        case .string(let text): json_write_string(out, text);
        case .array(let items):
            if items.len() == 0 { out.append("[]"); return; }
            out.append("[");
            for index in 0..<items.len() {
                if index > 0 { out.append(","); }
                json_break(out, indent, level + 1);
                json_write(out, items[index], indent, level + 1);
            }
            json_break(out, indent, level);
            out.append("]");
        case .object(let fields):
            if fields.len() == 0 { out.append("{}"); return; }
            out.append("{");
            var first = true;
            for entry in fields.entries() {
                if !first { out.append(","); }
                first = false;
                json_break(out, indent, level + 1);
                json_write_string(out, entry.key);
                out.append(":");
                if indent >= 0 { out.append(" "); }
                json_write(out, entry.value, indent, level + 1);
            }
            json_break(out, indent, level);
            out.append("}");
    }
}

def json_break(out: StringBuilder, indent: i32, level: i32) -> Void {
    if indent < 0 { return; }
    out.append("\n");
    out.append(" ".repeat(indent * level));
}

def json_write_string(out: StringBuilder, text: String) -> Void {
    let hex = "0123456789abcdef";
    out.append("\"");
    let length = text.len() as i32;
    var start = 0;
    for index in 0..<length {
        let byte = text.byte_at(index);
        if byte != 34 && byte != 92 && byte >= 32 { continue; }
        if index > start { out.append(text.substring(start, index - start)); }
        start = index + 1;
        switch byte {
            case 34: out.append("\\\"");
            case 92: out.append("\\\\");
            case 10: out.append("\\n");
            case 13: out.append("\\r");
            case 9: out.append("\\t");
            case 8: out.append("\\b");
            case 12: out.append("\\f");
            default: out.append("\\u00" + hex.substring(byte / 16, 1) + hex.substring(byte % 16, 1));
        }
    }
    if length > start { out.append(text.substring(start, length - start)); }
    out.append("\"");
}

struct JsonParser {
    let text: String;
    var at: i32;
    let length: i32;
    var depth: i32;

    def byte() -> i32 { if self.at < self.length { return self.text.byte_at(self.at); } -1 }
    def skip_space() -> Void {
        while self.at < self.length {
            let byte = self.text.byte_at(self.at);
            if byte != 32 && byte != 9 && byte != 10 && byte != 13 { return; }
            self.at += 1;
        }
    }
    def fail(message: String) -> Result<Json, JsonError> {
        var line = 1; var column = 1;
        for index in 0..<self.at {
            let byte = self.text.byte_at(index);
            if byte == 10 { line += 1; column = 1; } else if byte < 128 || byte >= 192 { column += 1; }
        }
        Result<Json, JsonError>.err(error: JsonError { message, line, column })
    }
    def value() -> Result<Json, JsonError> {
        let byte = self.byte();
        if byte == 123 || byte == 91 {
            if self.depth >= 512 { return self.fail("JSON nested too deeply"); }
            self.depth += 1;
            var result = Result<Json, JsonError>.ok(value: Json.null());
            if byte == 123 { result = self.object(); } else { result = self.array(); }
            self.depth -= 1;
            return result;
        }
        if byte == 34 {
            switch self.string() {
                case .ok(let text): return Result<Json, JsonError>.ok(value: Json.string(text));
                case .err(let error): return Result<Json, JsonError>.err(error: error);
            }
        }
        if byte == 45 || (byte >= 48 && byte <= 57) { return self.number(); }
        if self.word("true") { return Result<Json, JsonError>.ok(value: Json.bool(true)); }
        if self.word("false") { return Result<Json, JsonError>.ok(value: Json.bool(false)); }
        if self.word("null") { return Result<Json, JsonError>.ok(value: Json.null()); }
        if byte < 0 { return self.fail("unexpected end of JSON"); }
        self.fail("expected a JSON value")
    }
    def word(expected: String) -> Bool {
        let size = expected.len() as i32;
        if self.at + size > self.length || !self.text.substring(self.at, size).equals(expected) { return false; }
        self.at += size;
        true
    }
    def array() -> Result<Json, JsonError> {
        self.at += 1;
        let items = Vec<Json>.new();
        self.skip_space();
        if self.byte() == 93 { self.at += 1; return Result<Json, JsonError>.ok(value: Json.array(items)); }
        while true {
            self.skip_space();
            switch self.value() {
                case .ok(let item): items.push(item);
                case .err(let error): return Result<Json, JsonError>.err(error: error);
            }
            self.skip_space();
            let byte = self.byte();
            self.at += 1;
            if byte == 93 { break; }
            if byte != 44 { self.at -= 1; return self.fail("expected ',' or ']' in array"); }
        }
        Result<Json, JsonError>.ok(value: Json.array(items))
    }
    def object() -> Result<Json, JsonError> {
        self.at += 1;
        let fields = Dict<String, Json>.new();
        self.skip_space();
        if self.byte() == 125 { self.at += 1; return Result<Json, JsonError>.ok(value: Json.object(fields)); }
        while true {
            self.skip_space();
            if self.byte() != 34 { return self.fail("expected a string key in object"); }
            var key = "";
            switch self.string() {
                case .ok(let text): key = text;
                case .err(let error): return Result<Json, JsonError>.err(error: error);
            }
            self.skip_space();
            if self.byte() != 58 { return self.fail("expected ':' after object key"); }
            self.at += 1;
            self.skip_space();
            switch self.value() {
                case .ok(let item): fields[key] = item;
                case .err(let error): return Result<Json, JsonError>.err(error: error);
            }
            self.skip_space();
            let byte = self.byte();
            self.at += 1;
            if byte == 125 { break; }
            if byte != 44 { self.at -= 1; return self.fail("expected ',' or '}' in object"); }
        }
        Result<Json, JsonError>.ok(value: Json.object(fields))
    }
    def string() -> Result<String, JsonError> {
        self.at += 1;
        let out = StringBuilder.new();
        var start = self.at;
        while true {
            if self.at >= self.length { return self.string_error("unterminated string"); }
            let byte = self.text.byte_at(self.at);
            if byte == 34 { break; }
            if byte < 32 { return self.string_error("control character in string"); }
            if byte != 92 { self.at += 1; continue; }
            if self.at > start { out.append(self.text.substring(start, self.at - start)); }
            self.at += 1;
            let escape = self.byte();
            self.at += 1;
            switch escape {
                case 34: out.append("\"");
                case 92: out.append("\\");
                case 47: out.append("/");
                case 98: out.append_byte(8 as u8);
                case 102: out.append_byte(12 as u8);
                case 110: out.append("\n");
                case 114: out.append("\r");
                case 116: out.append("\t");
                case 117:
                    guard let unit = self.hex4() else { return self.string_error("invalid \\u escape"); }
                    var scalar = unit;
                    // A UTF-16 surrogate pair encodes one scalar.
                    if scalar >= 55296 && scalar <= 56319 {
                        if !self.word("\\u") { return self.string_error("unpaired surrogate in \\u escape"); }
                        guard let low = self.hex4() else { return self.string_error("invalid \\u escape"); }
                        if low < 56320 || low > 57343 { return self.string_error("unpaired surrogate in \\u escape"); }
                        scalar = 65536 + (scalar - 55296) * 1024 + (low - 56320);
                    } else if scalar >= 56320 && scalar <= 57343 {
                        return self.string_error("unpaired surrogate in \\u escape");
                    }
                    out.append(String.from_scalar(scalar));
                default: self.at -= 1; return self.string_error("invalid escape in string");
            }
            start = self.at;
        }
        if self.at > start { out.append(self.text.substring(start, self.at - start)); }
        self.at += 1;
        Result<String, JsonError>.ok(value: out.to_string())
    }
    def string_error(message: String) -> Result<String, JsonError> {
        switch self.fail(message) {
            case .err(let error): return Result<String, JsonError>.err(error: error);
            default: return Result<String, JsonError>.err(error: JsonError { message, line: 0, column: 0 });
        }
    }
    def hex4() -> i32? {
        if self.at + 4 > self.length { return nil; }
        var value = 0;
        for index in 0..<4 {
            let byte = self.text.byte_at(self.at + index);
            var digit = -1;
            if byte >= 48 && byte <= 57 { digit = byte - 48; }
            else if byte >= 97 && byte <= 102 { digit = byte - 87; }
            else if byte >= 65 && byte <= 70 { digit = byte - 55; }
            if digit < 0 { return nil; }
            value = value * 16 + digit;
        }
        self.at += 4;
        value
    }
    def number() -> Result<Json, JsonError> {
        let start = self.at;
        if self.byte() == 45 { self.at += 1; }
        if self.byte() == 48 { self.at += 1; }
        else if self.digits() == 0 { return self.fail("invalid number"); }
        var integral = true;
        if self.byte() == 46 {
            self.at += 1; integral = false;
            if self.digits() == 0 { return self.fail("expected digits after '.' in number"); }
        }
        if self.byte() == 101 || self.byte() == 69 {
            self.at += 1; integral = false;
            if self.byte() == 43 || self.byte() == 45 { self.at += 1; }
            if self.digits() == 0 { return self.fail("expected digits in number exponent"); }
        }
        let text = self.text.substring(start, self.at - start);
        // Integers within i64 stay exact; larger ones become floats.
        var digits = text; var limit = "9223372036854775807";
        if text.starts_with("-") { digits = text.substring(1, (text.len() as i32) - 1); limit = "9223372036854775808"; }
        if integral && (digits.len() < 19 || (digits.len() == 19 && digits <= limit)) {
            return Result<Json, JsonError>.ok(value: Json.int(text.to_i64()));
        }
        Result<Json, JsonError>.ok(value: Json.float(text.to_f64()))
    }
    def digits() -> i32 {
        var count = 0;
        while self.byte() >= 48 && self.byte() <= 57 { self.at += 1; count += 1; }
        count
    }
}
