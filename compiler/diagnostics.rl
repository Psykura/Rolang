// Diagnostic data, formatting and collection.
pub import "source.rl"
import "symbols.rl"
import "checker_core.rl"
import std.collections
import std.string_builder

pub enum Severity {
    case error; case warning; case note; case help;

    pub def label() -> String {
        switch self {
            case .error: "error"; case .warning: "warning";
            case .note: "note"; case .help: "help";
        }
    }
    pub def color_code() -> String {
        switch self {
            case .error: "1;31"; case .warning: "1;33";
            case .note: "1;36"; case .help: "1;34";
        }
    }
}

pub struct SourceLocation {
    pub var file_path: String;
    pub var line: i32;
    pub var column: i32;
    pub var end_line: i32? = nil;
    pub var end_column: i32? = nil;
}

pub struct Diagnostic {
    pub var severity: Severity;
    pub var message: String;
    pub var code: String? = nil;
    pub var location: SourceLocation? = nil;
    pub var source_line: String? = nil;
    pub var notes: Vec<String>;

    pub static def new(severity: Severity, message: String,
                       code: String? = nil, location: SourceLocation? = nil,
                       source_line: String? = nil, notes: Vec<String>? = nil) -> Diagnostic {
        Diagnostic { severity, message, code, location, source_line,
                     notes: notes ?? Vec<String>.new() }
    }
}

pub struct DiagnosticFormatter {
    pub let use_color: Bool;

    pub static def new(use_color: Bool = true) -> DiagnosticFormatter {
        DiagnosticFormatter { use_color }
    }
    def color(value: String, code: String) -> String {
        if !self.use_color { return value; }
        let result = StringBuilder.new();
        result.append_byte(27 as u8);
        result.append(f"[{code}m{value}");
        result.append_byte(27 as u8);
        result.append("[0m");
        result.to_string()
    }
    pub def format_diagnostic(diag: Diagnostic) -> String {
        let lines = Vec<String>.new();
        var header = self.color(diag.severity.label(), diag.severity.color_code());
        if let code = diag.code { if code.len() > 0 { header += f"[{code}]"; } }
        header += f": {self.color(diag.message, "1")}";
        lines.push(header);

        if let location = diag.location {
            lines.push(f"  --> {location.file_path}:{location.line}:{location.column}");
            if let source_line = diag.source_line {
                if source_line.len() > 0 {
                    let line_num = location.line.to_string();
                    let padding = " ".repeat(line_num.len() as i32);
                    lines.push(f"   {padding}|");
                    lines.push(f"   {line_num} | {source_line}");
                    let caret_padding = " ".repeat(location.column - 1);
                    var caret_count = 1;
                    if let end_column = location.end_column {
                        if end_column > location.column { caret_count = end_column - location.column; }
                    }
                    let carets = "^".repeat(caret_count);
                    lines.push(f"   {padding} | {caret_padding}{self.color(carets, "1;31")}");
                }
            }
        }
        for note in diag.notes {
            lines.push(f"   = {self.color("note", "1;36")}: {note}");
        }
        join_strings(lines, "\n")
    }
}

pub struct DiagnosticCollector {
    pub let source_files: Dict<String, String>;
    pub let diagnostics: Vec<Diagnostic>;
    pub var error_count: i32;
    pub var warning_count: i32;

    pub static def new(source_files: Dict<String, String>) -> DiagnosticCollector {
        DiagnosticCollector { source_files, diagnostics: Vec<Diagnostic>.new(),
                              error_count: 0, warning_count: 0 }
    }
    pub def has_errors() -> Bool { self.error_count > 0 }

    def source_line(path: String, line: i32) -> String? {
        if line < 1 { return nil; }
        if let content = self.source_files[path] {
            // CRLF is one break; the final break
            // does not produce an additional empty source line.
            var current = 1;
            var start = 0;
            var index = 0;
            let length = content.len() as i32;
            while index < length {
                let byte = content.byte_at(index);
                var width = 0;
                if byte == 13 {
                    width = 1;
                    if index + 1 < length && content.byte_at(index + 1) == 10 { width = 2; }
                } else if byte == 10 || byte == 11 || byte == 12 ||
                          byte == 28 || byte == 29 || byte == 30 { width = 1; }
                else if byte == 194 && index + 1 < length && content.byte_at(index + 1) == 133 { width = 2; }
                else if byte == 226 && index + 2 < length && content.byte_at(index + 1) == 128 {
                    let last = content.byte_at(index + 2);
                    if last == 168 || last == 169 { width = 3; }
                }
                if width > 0 {
                    if current == line { return content.substring(start, index - start); }
                    index += width;
                    start = index;
                    current += 1;
                } else { index += 1; }
            }
            if current == line && start < length { return content.substring(start, length - start); }
        }
        nil
    }

    def add(severity: Severity, message: String, file_path: String? = nil,
            span: Span? = nil, code: String? = nil,
            notes: Vec<String>? = nil) -> Void {
        var location: SourceLocation? = nil;
        var line: String? = nil;
        if let path = file_path {
            if let current = span {
                location = SourceLocation { file_path: path, line: current.line,
                    column: current.column, end_line: current.end_line,
                    end_column: current.end_column };
                line = self.source_line(path, current.line);
            }
        }
        self.diagnostics.push(Diagnostic.new(severity, message, code, location, line, notes));
        switch severity {
            case .error: self.error_count += 1;
            case .warning: self.warning_count += 1;
            default: {}
        }
    }

    pub def add_error(message: String, file_path: String? = nil,
                      span: Span? = nil, code: String? = nil,
                      notes: Vec<String>? = nil) -> Void {
        self.add(Severity.error(), message, file_path, span, code, notes);
    }
    pub def add_warning(message: String, file_path: String? = nil,
                        span: Span? = nil, code: String? = nil,
                        notes: Vec<String>? = nil) -> Void {
        self.add(Severity.warning(), message, file_path, span, code, notes);
    }
    pub def add_resolution_error(error: ResolutionError, file_path: String) -> Void {
        let code = switch error.kind {
            case .undefined_type: "E0001";
            case .undefined_value: "E0002";
            case .duplicate_type: "E0003";
            case .duplicate_value: "E0004";
        };
        self.add_error(error.message, file_path, error.span, code);
    }
    pub def add_type_error(error: TypeError, file_path: String) -> Void {
        let code = switch error.kind {
            case .type_mismatch: "E0101";
            case .undefined_member: "E0102";
            case .not_callable: "E0103";
            case .wrong_arg_count: "E0104";
            case .wrong_arg_type: "E0105";
            case .cannot_infer: "E0106";
            case .not_assignable: "E0107";
            case .invalid_operation: "E0108";
            case .not_a_type: "E0109";
            case .generic_arg_count: "E0110";
            default: "E0199";
        };
        self.add_error(error.message, file_path, error.span, code);
    }
    pub def add_parse_error(message: String, file_path: String,
                            line: i32 = 1, column: i32 = 1) -> Void {
        self.add_error(message, file_path, Span.new(line, column, line, column), "E0000");
    }
    pub def add_codegen_error(message: String) -> Void {
        self.add_error(message, nil, nil, "E0200");
    }
    pub def add_io_error(message: String, file_path: String? = nil) -> Void {
        if let path = file_path { self.add_error(f"{path}: {message}", nil, nil, "E0300"); }
        else { self.add_error(message, nil, nil, "E0300"); }
    }

    // The driver chooses the output stream; rendering remains deterministic.
    pub def emit_all(formatter: DiagnosticFormatter) -> String {
        let result = StringBuilder.new();
        for diag in self.diagnostics {
            result.append(formatter.format_diagnostic(diag));
            result.append("\n\n");
        }
        result.to_string()
    }
    pub def summary() -> String {
        let parts = Vec<String>.new();
        if self.error_count > 0 {
            var suffix = "";
            if self.error_count != 1 { suffix = "s"; }
            parts.push(f"{self.error_count} error{suffix}");
        }
        if self.warning_count > 0 {
            var suffix = "";
            if self.warning_count != 1 { suffix = "s"; }
            parts.push(f"{self.warning_count} warning{suffix}");
        }
        if parts.len() == 0 { return "no errors"; }
        join_strings(parts, " and ") + " generated"
    }
}
