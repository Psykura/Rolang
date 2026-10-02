// Compiler diagnostics and their terminal rendering.
pub import "source.rl"
import std.fs
import std.path
import std.string_builder

pub enum Severity {
    case error; case warning;

    pub def label() -> String {
        switch self { case .error: "error"; case .warning: "warning"; }
    }
    def color() -> String {
        switch self { case .error: "1;31"; case .warning: "1;33"; }
    }
}

pub struct Diagnostic {
    pub let severity: Severity;
    pub let message: String;
    pub let file: String?;
    pub let span: Span?;
    pub let notes: Vec<String>;

    pub static def error(message: String, file: String? = nil, span: Span? = nil,
                         notes: Vec<String> = Vec<String>.new()) -> Diagnostic {
        Diagnostic { severity: Severity.error(), message, file, span, notes }
    }
    pub static def warning(message: String, file: String? = nil, span: Span? = nil,
                           notes: Vec<String> = Vec<String>.new()) -> Diagnostic {
        Diagnostic { severity: Severity.warning(), message, file, span, notes }
    }
    pub def is_error() -> Bool {
        switch self.severity { case .error: true; default: false; }
    }
    // One-line form: `file:line:column: error: message`.
    pub def to_string() -> String {
        var location = "";
        if let file = self.file {
            location = file;
            if let span = self.span { location += f":{span.line}:{span.column}"; }
            location += ": ";
        }
        f"{location}{self.severity.label()}: {self.message}"
    }
}

pub def error_count(diagnostics: Vec<Diagnostic>) -> i32 {
    var count = 0;
    for diagnostic in diagnostics { if diagnostic.is_error() { count += 1; } }
    count
}

// Diagnostics grouped by file in order of first appearance, each file's in
// source order; those without a file keep their order at the end.
pub def sorted_diagnostics(diagnostics: Vec<Diagnostic>) -> Vec<Diagnostic> {
    let files = Vec<String>.new();
    for diagnostic in diagnostics { if let file = diagnostic.file {
        var seen = false;
        for known in files { if known.equals(file) { seen = true; } }
        if !seen { files.push(file); }
    } }
    let sorted = Vec<Diagnostic>.new();
    for file in files {
        let group = Vec<Diagnostic>.new();
        for diagnostic in diagnostics { if let other = diagnostic.file { if other.equals(file) { group.push(diagnostic); } } }
        for index in 1..<group.len() {
            var position = index;
            while position > 0 && position_before(group[position], group[position - 1]) {
                let moved = group[position];
                group[position] = group[position - 1];
                group[position - 1] = moved;
                position -= 1;
            }
        }
        for diagnostic in group { sorted.push(diagnostic); }
    }
    for diagnostic in diagnostics { if let file = diagnostic.file {} else { sorted.push(diagnostic); } }
    sorted
}

def position_before(first: Diagnostic, second: Diagnostic) -> Bool {
    guard let a = first.span else { return false; }
    guard let b = second.span else { return true; }
    a.line < b.line || (a.line == b.line && a.column < b.column)
}

// Renders a diagnostic with its source line and a caret underline:
//
//   error: Cannot assign String to i32 in variable initializer
//    --> main.rl:2:18
//     |
//   2 |     let a: i32 = "x";
//     |                  ^^^
pub struct DiagnosticRenderer {
    let color: Bool;
    let directory: String;
    let sources: Dict<String, String>;
    let lines: Dict<String, Vec<String>>;

    // `sources` maps file paths to text already in memory; other files are read on demand.
    pub static def new(color: Bool, sources: Dict<String, String> = Dict<String, String>.new()) -> DiagnosticRenderer {
        DiagnosticRenderer { color, directory: path_resolve(".") + "/", sources, lines: Dict<String, Vec<String>>.new() }
    }

    pub def render(diagnostic: Diagnostic) -> String {
        let out = StringBuilder.new();
        out.append(self.paint(diagnostic.severity.label(), diagnostic.severity.color()));
        out.append(self.paint(": " + diagnostic.message, "1"));
        var gutter = "";
        if let file = diagnostic.file {
            let shown = self.display_path(file);
            if let span = diagnostic.span {
                gutter = " ".repeat(span.line.to_string().len() as i32);
                out.append(f"\n{gutter}{self.paint("-->", "1;34")} {shown}:{span.line}:{span.column}");
                if let text = self.source_line(file, span.line) {
                    out.append(f"\n{gutter} {self.paint("|", "1;34")}");
                    out.append(f"\n{self.paint(span.line.to_string() + " |", "1;34")} {text.replace("\t", "    ")}");
                    out.append(f"\n{gutter} {self.paint("|", "1;34")} {self.underline(text, span, diagnostic.severity)}");
                }
            } else {
                out.append(f"\n{self.paint("-->", "1;34")} {shown}");
            }
        }
        for note in diagnostic.notes {
            out.append(f"\n{gutter} {self.paint("=", "1;34")} {self.paint("note", "1")}: {note}");
        }
        out.to_string()
    }

    // `2 errors generated.`, `1 warning generated.`, or "" when there is nothing to count.
    pub def summary(diagnostics: Vec<Diagnostic>) -> String {
        let errors = error_count(diagnostics);
        let warnings = diagnostics.len() - errors;
        let parts = Vec<String>.new();
        if warnings > 0 { parts.push(plural(warnings, "warning")); }
        if errors > 0 { parts.push(plural(errors, "error")); }
        if parts.len() == 0 { return ""; }
        var text = parts[0];
        if parts.len() > 1 { text += " and " + parts[1]; }
        text + " generated."
    }

    def underline(text: String, span: Span, severity: Severity) -> String {
        let scalars = text.scalars();
        var start = span.column - 1;
        if start > scalars.len() { start = scalars.len(); }
        var stop = scalars.len();
        if span.end_line == span.line && span.end_column > span.column { stop = span.end_column - 1; }
        if stop > scalars.len() { stop = scalars.len(); }
        var padding = 0;
        for index in 0..<start { padding += display_width(scalars[index]); }
        var width = 0;
        for index in start..<stop { width += display_width(scalars[index]); }
        if width == 0 { width = 1; }
        " ".repeat(padding) + self.paint("^".repeat(width), severity.color())
    }

    def source_line(file: String, line: i32) -> String? {
        if !self.lines.contains(file) {
            var text = self.sources[file];
            if let loaded = text {} else { text = fs_read_text(file); }
            let split = Vec<String>.new();
            if let content = text {
                for part in content.split("\n") {
                    if part.ends_with("\r") { split.push(part.substring(0, (part.len() - 1) as i32)); }
                    else { split.push(part); }
                }
            }
            self.lines[file] = split;
        }
        guard let lines = self.lines[file] else { return nil; }
        if line < 1 { return nil; }
        if line > lines.len() { return nil; }
        lines[line - 1]
    }

    def display_path(file: String) -> String {
        if file.starts_with(self.directory) {
            return file.substring(self.directory.len() as i32, (file.len() - self.directory.len()) as i32);
        }
        file
    }

    def paint(text: String, code: String) -> String {
        if !self.color { return text; }
        let out = StringBuilder.new();
        out.append_byte(27 as u8);
        out.append(f"[{code}m{text}");
        out.append_byte(27 as u8);
        out.append("[0m");
        out.to_string()
    }
}

def plural(count: i32, noun: String) -> String {
    if count == 1 { return f"1 {noun}"; }
    f"{count} {noun}s"
}

// Terminal columns: tabs render as four spaces and East Asian wide or emoji
// scalars take two cells.
def display_width(scalar: i32) -> i32 {
    if scalar == 9 { return 4; }
    if (scalar >= 4352 && scalar <= 4447) || (scalar >= 11904 && scalar <= 42191) ||
       (scalar >= 44032 && scalar <= 55203) || (scalar >= 63744 && scalar <= 64255) ||
       (scalar >= 65040 && scalar <= 65049) || (scalar >= 65072 && scalar <= 65135) ||
       (scalar >= 65280 && scalar <= 65376) || (scalar >= 65504 && scalar <= 65510) ||
       (scalar >= 127744 && scalar <= 129791) || (scalar >= 131072 && scalar <= 262141) { return 2; }
    1
}
