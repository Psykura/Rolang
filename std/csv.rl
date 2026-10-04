// Standard library: CSV (RFC 4180) reading and writing.
//
//     let rows = parse_csv("name,age\nada,36\n").ok_value() ?? [];
//     let people = csv_records("name,age\nada,36\n").ok_value() ?? [];   // [{"name": "ada", "age": "36"}]
//     let text = write_csv([["name", "note"], ["ada", "says \"hi\", twice"]]);
//
// Fields may be quoted with `"`; quoted fields may contain the delimiter,
// line breaks and doubled quotes. Lines end with \n or \r\n. Values are
// strings; convert numbers where they are used.
import "string.rl"
import "vec.rl"
import "dict.rl"
import "range.rl"
import "result.rl"
import "string_builder.rl"
import "json.rl"

pub struct CsvError {
    pub let message: String;
    // 1-based line where the problem is.
    pub let line: i32;
    pub def to_string() -> String { f"line {self.line}: {self.message}" }
}

// The rows of `text`. A final line break does not start an empty row.
pub def parse_csv(text: String, delimiter: String = ",") -> Result<Vec<Vec<String>>, CsvError> {
    let rows = Vec<Vec<String>>.new();
    if delimiter.len() != 1 { return Result<Vec<Vec<String>>, CsvError>.err(error: CsvError { message: "the delimiter must be one byte", line: 1 }); }
    let separator = delimiter.byte_at(0);
    let length = text.len() as i32;
    var row = Vec<String>.new();
    let field = StringBuilder.new();
    var line = 1;
    var index = 0;
    var row_started = false;
    while index < length {
        let byte = text.byte_at(index);
        if byte == 34 && field.len() == 0 {
            // A quoted field runs to the next quote that is not doubled.
            let opened = line;
            index += 1;
            var closed = false;
            while index < length {
                let inner = text.byte_at(index);
                if inner == 34 {
                    if index + 1 < length && text.byte_at(index + 1) == 34 { field.append("\""); index += 2; continue; }
                    closed = true; index += 1; break;
                }
                if inner == 10 { line += 1; }
                let start = index;
                while index < length && text.byte_at(index) != 34 && text.byte_at(index) != 10 { index += 1; }
                if index > start { field.append(text.substring(start, index - start)); }
                else { field.append(text.substring(index, 1)); index += 1; }
            }
            if !closed { return Result<Vec<Vec<String>>, CsvError>.err(error: CsvError { message: "unterminated quoted field", line: opened }); }
            row_started = true;
            if index < length {
                let after = text.byte_at(index);
                if after != separator && after != 10 && after != 13 {
                    return Result<Vec<Vec<String>>, CsvError>.err(error: CsvError { message: "unexpected character after a quoted field", line });
                }
            }
            continue;
        }
        if byte == separator {
            row.push(field.to_string()); field.clear(); row_started = true; index += 1; continue;
        }
        if byte == 13 && index + 1 < length && text.byte_at(index + 1) == 10 { index += 1; continue; }
        if byte == 10 {
            row.push(field.to_string()); field.clear();
            rows.push(row); row = Vec<String>.new(); row_started = false;
            line += 1; index += 1; continue;
        }
        if byte == 34 { return Result<Vec<Vec<String>>, CsvError>.err(error: CsvError { message: "quote inside an unquoted field", line }); }
        let start = index;
        while index < length {
            let next = text.byte_at(index);
            if next == separator || next == 10 || next == 13 || next == 34 { break; }
            index += 1;
        }
        field.append(text.substring(start, index - start));
        row_started = true;
    }
    if row_started || field.len() > 0 || row.len() > 0 { row.push(field.to_string()); rows.push(row); }
    Result<Vec<Vec<String>>, CsvError>.ok(value: rows)
}

// Rows after the header as records keyed by the header's names. Every row
// must have as many fields as the header.
pub def csv_records(text: String, delimiter: String = ",") -> Result<Vec<Dict<String, String>>, CsvError> {
    let records = Vec<Dict<String, String>>.new();
    switch parse_csv(text, delimiter) {
        case .err(let error): return Result<Vec<Dict<String, String>>, CsvError>.err(error: error);
        case .ok(let rows):
            if rows.len() == 0 { return Result<Vec<Dict<String, String>>, CsvError>.ok(value: records); }
            let header = rows[0];
            for index in 1..<rows.len() {
                let row = rows[index];
                if row.len() != header.len() {
                    return Result<Vec<Dict<String, String>>, CsvError>.err(error: CsvError { message: f"expected {header.len()} fields, found {row.len()}", line: index + 1 });
                }
                let record = Dict<String, String>.new();
                for column in 0..<header.len() { record[header[column]] = row[column]; }
                records.push(record);
            }
            return Result<Vec<Dict<String, String>>, CsvError>.ok(value: records);
    }
}

// One field, quoted when it contains the delimiter, a quote or a line break
// (or starts or ends with a space).
pub def csv_field(value: String, delimiter: String = ",") -> String {
    let length = value.len() as i32;
    var quote = length > 0 && (value.byte_at(0) == 32 || value.byte_at(length - 1) == 32);
    for index in 0..<length {
        let byte = value.byte_at(index);
        if byte == 34 || byte == 10 || byte == 13 || (delimiter.len() == 1 && byte == delimiter.byte_at(0)) { quote = true; break; }
    }
    if !quote { return value; }
    "\"" + value.replace("\"", "\"\"") + "\""
}

// Rows as CSV text, each line ending with `line_end`.
pub def write_csv(rows: Vec<Vec<String>>, delimiter: String = ",", line_end: String = "\n") -> String {
    let out = StringBuilder.new();
    for row in rows {
        for index in 0..<row.len() {
            if index > 0 { out.append(delimiter); }
            out.append(csv_field(row[index], delimiter));
        }
        out.append(line_end);
    }
    out.to_string()
}

// Encodable values as CSV: a header from the first value's members, then
// one row per value. Nested arrays and objects are written as JSON.
pub def encode_csv<T: Encodable>(values: Vec<T>, delimiter: String = ",") -> String {
    let rows = Vec<Vec<String>>.new();
    var header = Vec<String>.new();
    for value in values {
        guard let fields = value.to_json().as_object() else { continue; }
        if rows.len() == 0 { header = fields.keys(); rows.push(header); }
        let row = Vec<String>.new();
        for name in header {
            let item = fields[name] ?? Json.null();
            switch item {
                case .string(let text): row.push(text);
                case .null: row.push("");
                default: row.push(item.to_string());
            }
        }
        rows.push(row);
    }
    write_csv(rows, delimiter)
}
