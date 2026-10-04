// Standard library: leveled logging to stderr.
//
//     log_info("server started", ["port": "8080"]);
//     // 2026-10-04T12:00:00.125Z INFO  server started port=8080
//     let db = Logger.new("db");
//     db.warning("slow query", ["ms": "1200"]);
//     // 2026-10-04T12:00:01.002Z WARN  [db] slow query ms=1200
//
// Messages below the level are skipped; the level starts from the ROLANG_LOG
// environment variable (debug, info, warning, error or off), else info.
// set_log_json(true) writes one JSON object per line instead.
import "string.rl"
import "dict.rl"
import "vec.rl"
import "range.rl"
import "io.rl"
import "time.rl"
import "json.rl"
import "string_builder.rl"

pub extern "C" def rt_log_level() -> i32;
pub extern "C" def rt_log_set_level(level: i32) -> Void;
pub extern "C" def rt_log_json() -> i32;
pub extern "C" def rt_log_set_json(enabled: i32) -> Void;

pub enum LogLevel {
    case debug; case info; case warning; case error;
    pub def rank() -> i32 { switch self { case .debug: return 0; case .info: return 1; case .warning: return 2; case .error: return 3; } }
    pub def name() -> String { switch self { case .debug: return "debug"; case .info: return "info"; case .warning: return "warning"; case .error: return "error"; } }
    def label() -> String { switch self { case .debug: return "DEBUG"; case .info: return "INFO "; case .warning: return "WARN "; case .error: return "ERROR"; } }
}

// Logs at `level` and above; nil turns logging off.
pub def set_log_level(level: LogLevel?) -> Void {
    unsafe { rt_log_set_level(level?.rank() ?? 4); }
}
pub def set_log_json(enabled: Bool) -> Void {
    var flag = 0; if enabled { flag = 1; }
    unsafe { rt_log_set_json(flag); }
}
// Whether a message at `level` would be written, to skip building costly ones.
pub def log_enabled(level: LogLevel) -> Bool {
    unsafe { return level.rank() >= rt_log_level(); }
}

pub def log_debug(message: String, fields: Dict<String, String> = Dict<String, String>.new()) -> Void { write_log(LogLevel.debug, "", message, fields); }
pub def log_info(message: String, fields: Dict<String, String> = Dict<String, String>.new()) -> Void { write_log(LogLevel.info, "", message, fields); }
pub def log_warning(message: String, fields: Dict<String, String> = Dict<String, String>.new()) -> Void { write_log(LogLevel.warning, "", message, fields); }
pub def log_error(message: String, fields: Dict<String, String> = Dict<String, String>.new()) -> Void { write_log(LogLevel.error, "", message, fields); }

// A named source of log messages, shown with each one.
pub struct Logger {
    pub let name: String;
    pub static def new(name: String) -> Logger { Logger { name } }
    pub def debug(message: String, fields: Dict<String, String> = Dict<String, String>.new()) -> Void { write_log(LogLevel.debug, self.name, message, fields); }
    pub def info(message: String, fields: Dict<String, String> = Dict<String, String>.new()) -> Void { write_log(LogLevel.info, self.name, message, fields); }
    pub def warning(message: String, fields: Dict<String, String> = Dict<String, String>.new()) -> Void { write_log(LogLevel.warning, self.name, message, fields); }
    pub def error(message: String, fields: Dict<String, String> = Dict<String, String>.new()) -> Void { write_log(LogLevel.error, self.name, message, fields); }
}

// The line for one message: a UTC timestamp with milliseconds, the level,
// the logger's name, the message and `key=value` fields (quoted when needed).
pub def format_log(level: LogLevel, name: String, message: String, fields: Dict<String, String>, time: DateTime, json: Bool) -> String {
    let utc = time.to_utc();
    let stamp = utc.format("%Y-%m-%dT%H:%M:%S") + f".{utc.nanosecond / 1000000:03}Z";
    if json {
        let object = Json.empty_object();
        object.set("time", Json.string(stamp));
        object.set("level", Json.string(level.name()));
        if name.len() > 0 { object.set("logger", Json.string(name)); }
        object.set("message", Json.string(message));
        for entry in fields.entries() { object.set(entry.key, Json.string(entry.value)); }
        return object.to_string();
    }
    let out = StringBuilder.new();
    out.append(stamp); out.append(" "); out.append(level.label()); out.append(" ");
    if name.len() > 0 { out.append("["); out.append(name); out.append("] "); }
    out.append(message.replace("\n", "\\n"));
    for entry in fields.entries() { out.append(" "); out.append(entry.key); out.append("="); out.append(log_value(entry.value)); }
    out.to_string()
}

def log_value(value: String) -> String {
    var plain = value.len() > 0;
    for index in 0..<(value.len() as i32) {
        let byte = value.byte_at(index);
        if byte <= 32 || byte == 34 || byte == 61 || byte == 92 { plain = false; break; }
    }
    if plain { return value; }
    "\"" + value.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n") + "\""
}

def write_log(level: LogLevel, name: String, message: String, fields: Dict<String, String>) -> Void {
    if !log_enabled(level) { return; }
    var json = false;
    unsafe { json = rt_log_json() != 0; }
    eprintln(format_log(level, name, message, fields, DateTime.now(), json));
}
