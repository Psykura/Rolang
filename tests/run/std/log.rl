import std.io
import std.log
import std.time
def main() -> i32 {
    guard let t = DateTime.from_parts(2026, 10, 4, 12, 30, 5, 125000000) else { return 1; }
    println(format_log(LogLevel.info, "", "server started", ["port": "8080"], t, false));
    println(format_log(LogLevel.warning, "db", "slow query", ["sql": "select * from t", "ms": "1200"], t, false));
    println(format_log(LogLevel.error, "", "multi\nline", ["empty": "", "quote": "say \"hi\""], t, false));
    println(format_log(LogLevel.debug, "net", "sent", ["bytes": "12"], t, true));
    set_log_level(LogLevel.warning);
    println(f"{log_enabled(LogLevel.info)} {log_enabled(LogLevel.error)}");
    log_info("hidden");
    log_error("shown", ["code": "7"]);
    set_log_level(nil);
    log_error("hidden too");
    0
}
