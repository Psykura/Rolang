// Source scanner for the full-language parser. Tokens keep original spelling;
// the parser decides whether an identifier is a contextual keyword.
pub import "source.rl"

pub enum LexKind {
    case identifier; case integer; case floating; case string;
    case raw_string; case multiline_string; case interpolated_string;
    case interpolated_multiline_string; case character; case punctuation; case eof;

    pub def name() -> String {
        switch self {
            case .identifier: "identifier"; case .integer: "integer";
            case .floating: "floating"; case .string: "string";
            case .raw_string: "raw_string"; case .multiline_string: "multiline_string";
            case .interpolated_string: "interpolated_string";
            case .interpolated_multiline_string: "interpolated_multiline_string";
            case .character: "character"; case .punctuation: "punctuation";
            case .eof: "eof";
        }
    }
}

pub struct LexToken {
    pub let kind: LexKind;
    pub let text: String;
    pub let span: Span;
    pub let byte_start: i32;
    pub let byte_end: i32;
}

pub struct LexError { pub let message: String; pub let span: Span; }
pub struct LexResult { pub let tokens: Vec<LexToken>; pub let error: LexError?; }

struct Scanner {
    let source: String;
    let tokens: Vec<LexToken>;
    var index: i32;
    var line: i32;
    var column: i32;
    var nesting: i32;
    var error: LexError?;

    def length() -> i32 { self.source.len() as i32 }
    def peek(offset: i32 = 0) -> i32 {
        let index = self.index + offset;
        if index < 0 || index >= self.length() { return -1; }
        self.source.byte_at(index)
    }
    def advance() -> Void {
        let byte = self.peek();
        if byte < 0 { return; }
        self.index += 1;
        if byte == 10 { self.line += 1; self.column = 1; }
        else if byte < 128 || byte >= 192 { self.column += 1; }
    }
    def advance_many(count: i32) -> Void {
        for _ in 0..<count { self.advance(); }
    }
    def starts(text: String) -> Bool {
        let size = text.len() as i32;
        if self.index + size > self.length() { return false; }
        self.source.substring(self.index, size).equals(text)
    }
    def fail(message: String, start_line: i32, start_column: i32) -> Void {
        if let previous = self.error { return; }
        self.error = LexError { message, span: Span.new(start_line, start_column, self.line, self.column) };
    }
    def emit(kind: LexKind, start: i32, start_line: i32, start_column: i32) -> Void {
        self.tokens.push(LexToken {
            kind, text: self.source.substring(start, self.index - start),
            span: Span.new(start_line, start_column, self.line, self.column),
            byte_start: start, byte_end: self.index
        });
    }

    def skip_line_comment() -> Void {
        self.advance_many(2);
        while self.peek() >= 0 && self.peek() != 10 { self.advance(); }
    }
    def skip_block_comment(start_line: i32, start_column: i32) -> Void {
        self.advance_many(2);
        while self.peek() >= 0 {
            if self.starts("*/") { self.advance_many(2); return; }
            self.advance();
        }
        self.fail("unterminated block comment", start_line, start_column);
    }

    // Called with the opening quote under the cursor. Interpolation bodies
    // can contain nested strings and balanced braces; no rewriting happens.
    def quoted(quote: i32, triple: Bool, raw: Bool, interpolated: Bool,
               start_line: i32, start_column: i32) -> Bool {
        self.nesting += 1;
        defer { self.nesting -= 1; }
        if self.nesting > 128 {
            self.fail("string nesting limit exceeded", start_line, start_column);
            return false;
        }
        if triple { self.advance_many(3); } else { self.advance(); }
        while self.peek() >= 0 {
            if self.peek() == quote {
                if !triple { self.advance(); return true; }
                if self.peek(1) == quote && self.peek(2) == quote {
                    self.advance_many(3);
                    return true;
                }
            }
            if !raw && self.peek() == 92 {
                self.advance();
                if self.peek() >= 0 { self.advance(); }
                continue;
            }
            if interpolated && self.peek() == 123 {
                self.advance();
                if self.peek() == 123 { self.advance(); }
                else if !self.interpolation(start_line, start_column) { return false; }
                continue;
            }
            if interpolated && self.peek() == 125 {
                self.advance();
                if self.peek() == 125 { self.advance(); }
                else {
                    self.fail("unescaped '}' in interpolation", start_line, start_column);
                    return false;
                }
                continue;
            }
            self.advance();
        }
        self.fail("unterminated string", start_line, start_column);
        false
    }

    def interpolation(start_line: i32, start_column: i32) -> Bool {
        var braces = 1;
        while self.peek() >= 0 {
            let byte = self.peek();
            if byte == 34 || byte == 39 ||
               ((byte == 114 || byte == 102) && self.peek(1) == 34) {
                var raw = false;
                var nested_interpolation = false;
                if byte == 114 || byte == 102 {
                    raw = byte == 114;
                    nested_interpolation = byte == 102;
                    self.advance();
                }
                let quote = self.peek();
                let triple = quote == 34 && self.peek(1) == 34 && self.peek(2) == 34;
                if !self.quoted(quote, triple, raw, nested_interpolation,
                                start_line, start_column) { return false; }
                continue;
            }
            if self.starts("//") { self.skip_line_comment(); continue; }
            if self.starts("/*") {
                self.skip_block_comment(start_line, start_column);
                if let error = self.error { return false; }
                continue;
            }
            if byte == 123 { braces += 1; }
            if byte == 125 {
                braces -= 1;
                self.advance();
                if braces == 0 { return true; }
                continue;
            }
            self.advance();
        }
        self.fail("unterminated interpolation", start_line, start_column);
        false
    }

    def scan_string(start: i32, start_line: i32, start_column: i32,
                    raw: Bool, interpolated: Bool, prefixed: Bool) -> Void {
        if prefixed { self.advance(); }
        let triple = self.peek() == 34 && self.peek(1) == 34 && self.peek(2) == 34;
        if !self.quoted(34, triple, raw, interpolated, start_line, start_column) { return; }
        if interpolated {
            if triple { self.emit(LexKind.interpolated_multiline_string(), start, start_line, start_column); }
            else { self.emit(LexKind.interpolated_string(), start, start_line, start_column); }
        } else if raw { self.emit(LexKind.raw_string(), start, start_line, start_column); }
        else if triple { self.emit(LexKind.multiline_string(), start, start_line, start_column); }
        else { self.emit(LexKind.string(), start, start_line, start_column); }
    }

    def scan_character(start: i32, start_line: i32, start_column: i32) -> Void {
        self.advance();
        var count = 0;
        while self.peek() >= 0 && self.peek() != 39 {
            if self.peek() == 92 {
                self.advance();
                if self.peek() < 0 { break; }
                self.advance();
                count += 1;
            } else {
                let byte = self.peek();
                self.advance();
                if byte < 128 || byte >= 192 { count += 1; }
            }
            if count > 1 { break; }
        }
        if self.peek() == 39 && count <= 1 {
            self.advance();
            if count == 1 { self.emit(LexKind.character(), start, start_line, start_column); return; }
        }
        self.fail("invalid character literal", start_line, start_column);
    }

    def scan_number(start: i32, start_line: i32, start_column: i32) -> Void {
        if self.peek() == 48 {
            let radix = self.peek(1);
            var base = 0;
            if radix == 120 || radix == 88 { base = 16; }
            if radix == 98 || radix == 66 { base = 2; }
            if radix == 111 || radix == 79 { base = 8; }
            if base > 0 && digit_for_base(self.peek(2), base) {
                self.advance_many(3);
                while digit_for_base(self.peek(), base) || self.peek() == 95 { self.advance(); }
                self.emit(LexKind.integer(), start, start_line, start_column);
                return;
            }
        }
        while decimal_digit(self.peek()) || self.peek() == 95 { self.advance(); }
        var floating = false;
        if self.peek() == 46 && decimal_digit(self.peek(1)) {
            floating = true;
            self.advance();
            while decimal_digit(self.peek()) || self.peek() == 95 { self.advance(); }
        }
        if self.peek() == 101 || self.peek() == 69 {
            var offset = 1;
            if self.peek(offset) == 43 || self.peek(offset) == 45 { offset += 1; }
            if decimal_digit(self.peek(offset)) {
                floating = true;
                self.advance_many(offset + 1);
                while decimal_digit(self.peek()) { self.advance(); }
            }
        }
        if floating { self.emit(LexKind.floating(), start, start_line, start_column); }
        else { self.emit(LexKind.integer(), start, start_line, start_column); }
    }

    def scan_punctuation(start: i32, start_line: i32, start_column: i32) -> Void {
        for spelling in ["..<", "...", "<<=", ">>="] {
            if self.starts(spelling) {
                self.advance_many(3);
                self.emit(LexKind.punctuation(), start, start_line, start_column);
                return;
            }
        }
        for spelling in ["?.", "??", "->", "==", "!=", "<=", ">=", "&&", "||",
                         "<<", ">>", "+=", "-=", "*=", "/=", "%=", "&=", "|=", "^="] {
            if self.starts(spelling) {
                self.advance_many(2);
                self.emit(LexKind.punctuation(), start, start_line, start_column);
                return;
            }
        }
        let byte = self.peek();
        if byte >= 0 && "(){}[];,:.+-*/%!=<>?&|^~".find(self.source.substring(self.index, 1)) >= 0 {
            self.advance();
            self.emit(LexKind.punctuation(), start, start_line, start_column);
            return;
        }
        self.fail("unsupported character", start_line, start_column);
    }

    def scan_token() -> Void {
        let byte = self.peek();
        if byte == 32 || byte == 9 || byte == 13 || byte == 10 {
            self.advance();
            return;
        }
        let start = self.index;
        let start_line = self.line;
        let start_column = self.column;
        if self.starts("//") { self.skip_line_comment(); return; }
        if self.starts("/*") { self.skip_block_comment(start_line, start_column); return; }
        if (byte == 114 || byte == 102) && self.peek(1) == 34 {
            self.scan_string(start, start_line, start_column, byte == 114, byte == 102, true);
            return;
        }
        if byte == 34 { self.scan_string(start, start_line, start_column, false, false, false); return; }
        if byte == 39 { self.scan_character(start, start_line, start_column); return; }
        if identifier_start(byte) {
            self.advance();
            while identifier_start(self.peek()) || decimal_digit(self.peek()) { self.advance(); }
            let word = self.source.substring(start, self.index - start);
            if word.equals("as") && (self.peek() == 63 || self.peek() == 33) {
                self.advance();
                self.emit(LexKind.punctuation(), start, start_line, start_column);
            } else { self.emit(LexKind.identifier(), start, start_line, start_column); }
            return;
        }
        if decimal_digit(byte) { self.scan_number(start, start_line, start_column); return; }
        self.scan_punctuation(start, start_line, start_column);
    }
}

pub def identifier_start(byte: i32) -> Bool {
    (byte >= 65 && byte <= 90) || (byte >= 97 && byte <= 122) || byte == 95
}
pub def decimal_digit(byte: i32) -> Bool { byte >= 48 && byte <= 57 }
def digit_for_base(byte: i32, base: i32) -> Bool {
    if decimal_digit(byte) { return byte - 48 < base; }
    if base == 16 {
        return (byte >= 65 && byte <= 70) || (byte >= 97 && byte <= 102);
    }
    false
}

pub def tokenize(source: String) -> LexResult {
    let tokens = Vec<LexToken>.new();
    if source.len() > 2147483646 {
        return LexResult { tokens, error: LexError {
            message: "source file too large", span: Span.new(1, 1)
        } };
    }
    let scanner = Scanner {
        source, tokens, index: 0, line: 1, column: 1, nesting: 0, error: nil
    };
    while scanner.index < scanner.length() {
        if let error = scanner.error { break; }
        scanner.scan_token();
    }
    tokens.push(LexToken {
        kind: LexKind.eof(), text: "", span: Span.new(scanner.line, scanner.column, scanner.line, scanner.column),
        byte_start: scanner.index, byte_end: scanner.index
    });
    LexResult { tokens, error: scanner.error }
}
