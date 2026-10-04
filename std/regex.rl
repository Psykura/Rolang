// Standard library: regular expressions.
//
//     guard let date = Regex.new(r"(?<year>\d{4})-(?<month>\d\d)-(?<day>\d\d)").ok_value() else { return 1; }
//     if let found = date.find("released 2026-10-04") { println(found.named("year") ?? ""); }
//     date.replace_all(text, "${day}.${month}.${year}")
//
// Syntax: literals, `.`, classes `[a-z]` and `[^...]`, `\d \w \s` and their
// negations `\D \W \S`, anchors `^ $ \A \z`, word boundaries `\b \B`, groups
// `(...)`, `(?:...)` and `(?<name>...)` (or `(?P<name>...)`), alternation `|`,
// repetition `* + ? {n} {n,} {n,m}` (lazy with a trailing `?`), escapes
// `\n \t \r \xHH \x{HHHH}`, and flags `(?i)` ignore case, `(?m)` ^ and $ at
// line breaks, `(?s)` `.` matches a newline (also `(?i:...)` for a group).
// Matching takes time linear in the text for every pattern; there are no
// backreferences or lookaround. Matches are leftmost-first, as in Perl and
// Python, except that `$` without (?m) matches only at the end of the text
// (not before a final newline), and a group inside a repetition that can
// match nothing may report an earlier iteration's text in rare cases. Text
// is UTF-8: `.` and classes match one code point, and positions are byte
// offsets.
import "string.rl"
import "result.rl"
import "vec.rl"
import "range.rl"
import "string_builder.rl"

pub extern "C" def rt_regex_failure() -> RawPtr;
pub extern "C" def rt_regex_compile(pattern: String, flags: i32) -> RawPtr;
pub extern "C" def rt_regex_free(regex: RawPtr) -> Void;
pub extern "C" def rt_regex_groups(regex: RawPtr) -> i32;
pub extern "C" def rt_regex_group_index(regex: RawPtr, name: String) -> i32;
pub extern "C" def rt_regex_group_name(regex: RawPtr, index: i32) -> RawPtr;
pub extern "C" def rt_regex_search(regex: RawPtr, text: String, start: i64) -> i32;
pub extern "C" def rt_regex_capture_start(regex: RawPtr, index: i32) -> i64;
pub extern "C" def rt_regex_capture_end(regex: RawPtr, index: i32) -> i64;

pub struct RegexError {
    pub let message: String;
    pub def to_string() -> String { self.message }
}

// One match: the whole match is group 0, capturing groups are numbered from 1.
pub struct Match {
    let subject: String;
    let starts: Vec<i32>;
    let ends: Vec<i32>;
    let regex: Regex;

    // Byte offsets of the whole match.
    pub def start() -> i32 { self.starts[0] }
    pub def end() -> i32 { self.ends[0] }
    pub def text() -> String { self.subject.substring(self.starts[0], self.ends[0] - self.starts[0]) }
    // A group's text; nil when the group did not take part in the match.
    pub def group(index: i32) -> String? {
        if index < 0 || index >= self.starts.len() as i32 || self.starts[index] < 0 { return nil; }
        self.subject.substring(self.starts[index], self.ends[index] - self.starts[index])
    }
    pub def named(name: String) -> String? {
        let index = self.regex.group_index(name);
        if index < 0 { return nil; }
        self.group(index)
    }
    // Byte offsets of a group, or nil.
    pub def span(index: i32) -> (i32, i32)? {
        if index < 0 || index >= self.starts.len() as i32 || self.starts[index] < 0 { return nil; }
        (self.starts[index], self.ends[index])
    }
    // Groups 1 and up.
    pub def groups() -> Vec<String?> {
        let out = Vec<String?>.new();
        for index in 1..<(self.starts.len() as i32) { out.push(self.group(index)); }
        out
    }
}

pub struct Regex {
    var handle: RawPtr;
    pub let pattern: String;

    pub static def new(pattern: String, ignore_case: Bool = false, multiline: Bool = false, dot_all: Bool = false) -> Result<Regex, RegexError> {
        var flags = 0;
        if ignore_case { flags = flags | 1; }
        if multiline { flags = flags | 2; }
        if dot_all { flags = flags | 4; }
        unsafe {
            let handle = rt_regex_compile(pattern, flags);
            if (handle as i64) == 0 {
                return Result<Regex, RegexError>.err(error: RegexError { message: f"invalid pattern {pattern}: {String.from_handle(rt_regex_failure())}" });
            }
            return Result<Regex, RegexError>.ok(value: Regex { handle, pattern });
        }
    }
    pub def __release__() -> Void {
        unsafe {
            let handle = self.handle;
            self.handle = 0 as RawPtr;
            rt_regex_free(handle);
        }
    }

    // The number of capturing groups.
    pub def group_count() -> i32 { unsafe { return rt_regex_groups(self.handle); } }
    // The number of the group called `name`, or -1.
    pub def group_index(name: String) -> i32 { unsafe { return rt_regex_group_index(self.handle, name); } }
    // Group names by number; empty for unnamed groups.
    pub def group_names() -> Vec<String> {
        let out = Vec<String>.new();
        for index in 1...self.group_count() { unsafe { out.push(String.from_handle(rt_regex_group_name(self.handle, index))); } }
        out
    }

    pub def is_match(text: String) -> Bool {
        unsafe { return rt_regex_search(self.handle, text, 0) != 0; }
    }
    // The first match at or after byte `start`.
    pub def find(text: String, start: i32 = 0) -> Match? {
        unsafe {
            if rt_regex_search(self.handle, text, start as i64) == 0 { return nil; }
            let starts = Vec<i32>.new(); let ends = Vec<i32>.new();
            for index in 0...rt_regex_groups(self.handle) {
                starts.push(rt_regex_capture_start(self.handle, index) as i32);
                ends.push(rt_regex_capture_end(self.handle, index) as i32);
            }
            return Match { subject: text, starts, ends, regex: self };
        }
    }
    // Every non-overlapping match, left to right.
    pub def find_all(text: String) -> Vec<Match> {
        let out = Vec<Match>.new();
        var start = 0;
        let length = text.len() as i32;
        while start <= length {
            guard let found = self.find(text, start) else { break; }
            out.push(found);
            if found.end() > found.start() { start = found.end(); }
            else {
                // An empty match: continue after the next character.
                if found.end() >= length { break; }
                start = found.end() + utf8_width(text.byte_at(found.end()));
            }
        }
        out
    }
    // The first match replaced: `$1` or `${1}` and `${name}` insert groups, `$$` a dollar sign.
    pub def replace(text: String, replacement: String) -> String {
        guard let found = self.find(text) else { return text; }
        text.substring(0, found.start()) + expand(found, replacement) + text.substring(found.end(), (text.len() as i32) - found.end())
    }
    // Every match replaced, as in replace().
    pub def replace_all(text: String, replacement: String) -> String {
        self.replace_with(text, (found: Match) -> { expand(found, replacement) })
    }
    // Every match replaced by what `f` returns for it.
    pub def replace_with(text: String, f: (Match) -> String) -> String {
        let out = StringBuilder.new();
        var last = 0;
        for found in self.find_all(text) {
            out.append(text.substring(last, found.start() - last));
            out.append(f(found));
            last = found.end();
        }
        out.append(text.substring(last, (text.len() as i32) - last));
        out.to_string()
    }
    // The text between matches.
    pub def split(text: String) -> Vec<String> {
        let out = Vec<String>.new();
        var last = 0;
        for found in self.find_all(text) {
            if found.end() == found.start() && (found.start() == 0 || found.start() == text.len() as i32) { continue; }
            out.push(text.substring(last, found.start() - last));
            last = found.end();
        }
        out.push(text.substring(last, (text.len() as i32) - last));
        out
    }
}

def utf8_width(byte: i32) -> i32 {
    if byte >= 240 { return 4; }
    if byte >= 224 { return 3; }
    if byte >= 192 { return 2; }
    1
}

def expand(found: Match, replacement: String) -> String {
    let out = StringBuilder.new();
    let length = replacement.len() as i32;
    var index = 0;
    while index < length {
        let byte = replacement.byte_at(index);
        if byte != 36 || index + 1 >= length { out.append(replacement.substring(index, 1)); index += 1; continue; }
        let next = replacement.byte_at(index + 1);
        if next == 36 { out.append("$"); index += 2; continue; }
        if next == 123 {
            let close = replacement.find_from("}", index + 2);
            if close < 0 { out.append("$"); index += 1; continue; }
            let name = replacement.substring(index + 2, close - index - 2);
            var number = -1;
            if name.len() > 0 { number = 0; for position in 0..<(name.len() as i32) { let digit = name.byte_at(position); if digit < 48 || digit > 57 { number = -1; break; } number = number * 10 + digit - 48; } }
            if number >= 0 { out.append(found.group(number) ?? ""); } else { out.append(found.named(name) ?? ""); }
            index = close + 1;
            continue;
        }
        if next >= 48 && next <= 57 {
            out.append(found.group(next - 48) ?? "");
            index += 2;
            continue;
        }
        out.append("$"); index += 1;
    }
    out.to_string()
}

// `text` with every character that has a meaning in patterns escaped.
pub def regex_escape(text: String) -> String {
    let out = StringBuilder.new();
    for index in 0..<(text.len() as i32) {
        let piece = text.substring(index, 1);
        if "\\.+*?()|[]{}^$-#&~".contains(piece) { out.append("\\"); }
        out.append(piece);
    }
    out.to_string()
}
