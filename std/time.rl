// Standard library: durations, clocks and calendar dates.
//
//     let start = Instant.now();
//     work();
//     println(f"took {start.elapsed()}");          // e.g. "12.5ms"
//     let now = DateTime.now();                     // UTC
//     println(now.to_string());                     // "2026-10-02T19:39:30.25Z"
//
// Instant is monotonic and only meaningful within one process. DateTime is a
// proleptic Gregorian date and time with a fixed UTC offset; leap seconds are
// not represented. TimeZone reads the IANA time zone database:
//
//     guard let tokyo = TimeZone.load("Asia/Tokyo").ok_value() else { return 1; }
//     println(DateTime.now().in_zone(tokyo).to_string());   // "2026-10-05T04:39:30.25+09:00"
//     let meeting = TimeZone.load("Europe/Berlin").ok_value()?.instant(2026, 3, 29, 2, 30);
import "string.rl"
import "vec.rl"
import "range.rl"
import "task.rl"
import "result.rl"
import "fs.rl"
import "process.rl"

pub extern "C" def rt_time_monotonic_ns() -> i64;
pub extern "C" def rt_time_unix_ns() -> i64;
pub extern "C" def rt_time_sleep_ns(nanoseconds: i64) -> Void;
pub extern "C" def rt_time_utc_offset(unix_seconds: i64) -> i32;

// A signed span of time with nanosecond resolution (about ±292 years).
pub struct Duration {
    pub let nanoseconds: i64;

    pub static def zero() -> Duration { Duration { nanoseconds: 0 } }
    pub static def nanos(count: i64) -> Duration { Duration { nanoseconds: count } }
    pub static def micros(count: i64) -> Duration { Duration { nanoseconds: count * 1000 } }
    pub static def millis(count: i64) -> Duration { Duration { nanoseconds: count * 1000000 } }
    pub static def seconds(count: i64) -> Duration { Duration { nanoseconds: count * 1000000000 } }
    pub static def minutes(count: i64) -> Duration { Duration.seconds(count * 60) }
    pub static def hours(count: i64) -> Duration { Duration.seconds(count * 3600) }
    pub static def days(count: i64) -> Duration { Duration.seconds(count * 86400) }
    // Rounded to the nearest nanosecond.
    pub static def from_seconds(value: f64) -> Duration {
        var scaled = value * 1000000000.0;
        if scaled >= 0.0 { scaled += 0.5; } else { scaled -= 0.5; }
        Duration { nanoseconds: scaled as i64 }
    }

    pub def as_seconds() -> f64 { (self.nanoseconds as f64) / 1000000000.0 }
    pub def as_millis() -> f64 { (self.nanoseconds as f64) / 1000000.0 }
    // Truncated toward zero.
    pub def whole_seconds() -> i64 { self.nanoseconds / 1000000000 }
    pub def whole_millis() -> i64 { self.nanoseconds / 1000000 }
    pub def whole_micros() -> i64 { self.nanoseconds / 1000 }
    pub def is_negative() -> Bool { self.nanoseconds < 0 }
    pub def abs() -> Duration { if self.nanoseconds < 0 { return Duration { nanoseconds: 0 - self.nanoseconds }; } self }

    pub def __add__(other: Duration) -> Duration { Duration { nanoseconds: self.nanoseconds + other.nanoseconds } }
    pub def __sub__(other: Duration) -> Duration { Duration { nanoseconds: self.nanoseconds - other.nanoseconds } }
    pub def __neg__() -> Duration { Duration { nanoseconds: 0 - self.nanoseconds } }
    pub def times(factor: i64) -> Duration { Duration { nanoseconds: self.nanoseconds * factor } }
    pub def divided_by(divisor: i64) -> Duration { Duration { nanoseconds: self.nanoseconds / divisor } }
    pub def __eq__(other: Duration) -> Bool { self.nanoseconds == other.nanoseconds }
    pub def __ne__(other: Duration) -> Bool { self.nanoseconds != other.nanoseconds }
    pub def __lt__(other: Duration) -> Bool { self.nanoseconds < other.nanoseconds }
    pub def __le__(other: Duration) -> Bool { self.nanoseconds <= other.nanoseconds }
    pub def __gt__(other: Duration) -> Bool { self.nanoseconds > other.nanoseconds }
    pub def __ge__(other: Duration) -> Bool { self.nanoseconds >= other.nanoseconds }

    // The largest fitting unit with up to three decimals: "1.5s", "250ms",
    // "12.345µs", "800ns", "2m5s", "1h30m".
    pub def to_string() -> String {
        let total = self.abs().nanoseconds;
        var sign = ""; if self.nanoseconds < 0 { sign = "-"; }
        if total >= 60000000000 {
            let seconds = total / 1000000000;
            let hours = seconds / 3600;
            let minutes = (seconds % 3600) / 60;
            let rest = Duration { nanoseconds: total % 60000000000 };
            var text = sign;
            if hours > 0 { text += f"{hours}h"; }
            if minutes > 0 { text += f"{minutes}m"; }
            if rest.nanoseconds > 0 { text += rest.to_string(); }
            return text;
        }
        if total >= 1000000000 { return sign + scaled_text(total, 1000000000) + "s"; }
        if total >= 1000000 { return sign + scaled_text(total, 1000000) + "ms"; }
        if total >= 1000 { return sign + scaled_text(total, 1000) + "µs"; }
        f"{sign}{total}ns"
    }
}

// `value / unit` with up to three decimals, trailing zeros removed.
def scaled_text(value: i64, unit: i64) -> String {
    let whole = value / unit;
    let fraction = ((value % unit) * 1000) / unit;
    if fraction == 0 { return whole.to_string(); }
    var digits = f"{fraction:03}";
    while digits.ends_with("0") { digits = digits.substring(0, (digits.len() as i32) - 1); }
    f"{whole}.{digits}"
}

// A point on the monotonic clock, for measuring elapsed time.
pub struct Instant {
    pub let nanoseconds: i64;

    pub static def now() -> Instant {
        unsafe { return Instant { nanoseconds: rt_time_monotonic_ns() }; }
    }
    pub def elapsed() -> Duration { Instant.now().since(self) }
    pub def since(earlier: Instant) -> Duration { Duration { nanoseconds: self.nanoseconds - earlier.nanoseconds } }
    pub def __add__(span: Duration) -> Instant { Instant { nanoseconds: self.nanoseconds + span.nanoseconds } }
    pub def __lt__(other: Instant) -> Bool { self.nanoseconds < other.nanoseconds }
    pub def __eq__(other: Instant) -> Bool { self.nanoseconds == other.nanoseconds }
}

// Blocks the current thread. Async code should use sleep_for, which lets
// other tasks run.
pub def sleep_blocking(duration: Duration) -> Void {
    unsafe { rt_time_sleep_ns(duration.nanoseconds); }
}

pub def sleep_for(duration: Duration) async -> Void {
    var millis = duration.whole_millis();
    if millis == 0 && duration.nanoseconds > 0 { millis = 1; }
    await sleep(millis);
}

// The task's result, or nil after cancelling it when it takes longer than `limit`.
pub def with_timeout<T>(task: Task<T>, limit: Duration) async -> T? {
    let watchdog = spawn cancel_after(task, limit);
    let finished = await task.wait();
    watchdog.cancel();
    if !finished { return nil; }
    await task
}

def cancel_after<T>(task: Task<T>, limit: Duration) async -> Void {
    await sleep_for(limit);
    task.cancel();
}

// A calendar date and time at a fixed offset from UTC.
pub struct DateTime {
    pub let year: i32;
    // 1 to 12.
    pub let month: i32;
    pub let day: i32;
    pub let hour: i32;
    pub let minute: i32;
    pub let second: i32;
    pub let nanosecond: i32;
    // Seconds east of UTC; 0 for UTC.
    pub let offset_seconds: i32;

    // The current time in UTC.
    pub static def now() -> DateTime {
        unsafe { return DateTime.from_unix_nanos(rt_time_unix_ns(), 0); }
    }
    // The current time in the local time zone.
    pub static def now_local() -> DateTime {
        unsafe {
            let nanos = rt_time_unix_ns();
            return DateTime.from_unix_nanos(nanos, rt_time_utc_offset(floor_div(nanos, 1000000000)));
        }
    }
    pub static def from_unix(seconds: i64, offset_seconds: i32 = 0) -> DateTime {
        DateTime.from_unix_nanos(seconds * 1000000000, offset_seconds)
    }
    pub static def from_unix_nanos(nanos: i64, offset_seconds: i32 = 0) -> DateTime {
        let local = floor_div(nanos, 1000000000) + (offset_seconds as i64);
        let days = floor_div(local, 86400);
        let seconds = local - days * 86400;
        let date = civil_from_days(days);
        DateTime { year: date.0, month: date.1, day: date.2,
            hour: (seconds / 3600) as i32, minute: ((seconds % 3600) / 60) as i32, second: (seconds % 60) as i32,
            nanosecond: (nanos - floor_div(nanos, 1000000000) * 1000000000) as i32, offset_seconds }
    }
    // nil for an invalid date or time.
    pub static def from_parts(year: i32, month: i32, day: i32, hour: i32 = 0, minute: i32 = 0, second: i32 = 0,
                              nanosecond: i32 = 0, offset_seconds: i32 = 0) -> DateTime? {
        if month < 1 || month > 12 || day < 1 || day > days_in_month(year, month) { return nil; }
        if hour < 0 || hour > 23 || minute < 0 || minute > 59 || second < 0 || second > 59 { return nil; }
        if nanosecond < 0 || nanosecond > 999999999 { return nil; }
        DateTime { year, month, day, hour, minute, second, nanosecond, offset_seconds }
    }
    // An RFC 3339 timestamp such as 2026-10-02T19:39:30Z or
    // 2026-10-02 20:39:30.5+01:00; nil when malformed.
    pub static def parse(text: String) -> DateTime? {
        let parser = DateParser { text, at: 0 };
        guard let year = parser.number(4) else { return nil; }
        if !parser.take("-") { return nil; }
        guard let month = parser.number(2) else { return nil; }
        if !parser.take("-") { return nil; }
        guard let day = parser.number(2) else { return nil; }
        if !(parser.take("T") || parser.take("t") || parser.take(" ")) { return nil; }
        guard let hour = parser.number(2) else { return nil; }
        if !parser.take(":") { return nil; }
        guard let minute = parser.number(2) else { return nil; }
        if !parser.take(":") { return nil; }
        guard let second = parser.number(2) else { return nil; }
        var nanosecond = 0;
        if parser.take(".") {
            var digits = 0;
            while parser.at < (text.len() as i32) && is_ascii_digit(text.byte_at(parser.at)) {
                if digits < 9 { nanosecond = nanosecond * 10 + text.byte_at(parser.at) - 48; }
                digits += 1; parser.at += 1;
            }
            if digits == 0 { return nil; }
            while digits < 9 { nanosecond *= 10; digits += 1; }
        }
        var offset = 0;
        if parser.take("Z") || parser.take("z") {}
        else {
            var sign = 1;
            if parser.take("-") { sign = -1; } else if !parser.take("+") { return nil; }
            guard let hours = parser.number(2) else { return nil; }
            if !parser.take(":") { return nil; }
            guard let minutes = parser.number(2) else { return nil; }
            offset = sign * (hours * 3600 + minutes * 60);
        }
        if parser.at != (text.len() as i32) { return nil; }
        DateTime.from_parts(year, month, day, hour, minute, second, nanosecond, offset)
    }

    // Seconds since 1970-01-01T00:00:00Z.
    pub def unix_seconds() -> i64 {
        let days = days_from_civil(self.year, self.month, self.day);
        days * 86400 + (self.hour as i64) * 3600 + (self.minute as i64) * 60 + (self.second as i64) - (self.offset_seconds as i64)
    }
    pub def unix_nanos() -> i64 { self.unix_seconds() * 1000000000 + (self.nanosecond as i64) }
    // The same instant at another offset.
    pub def with_offset(offset_seconds: i32) -> DateTime { DateTime.from_unix_nanos(self.unix_nanos(), offset_seconds) }
    pub def to_utc() -> DateTime { self.with_offset(0) }
    // ISO weekday: 1 is Monday, 7 is Sunday.
    pub def weekday() -> i32 {
        // 1970-01-01 was a Thursday.
        let shifted = days_from_civil(self.year, self.month, self.day) + 3;
        (shifted - floor_div(shifted, 7) * 7 + 1) as i32
    }
    // 1 to 366.
    pub def day_of_year() -> i32 {
        (days_from_civil(self.year, self.month, self.day) - days_from_civil(self.year, 1, 1) + 1) as i32
    }
    pub def __add__(span: Duration) -> DateTime { DateTime.from_unix_nanos(self.unix_nanos() + span.nanoseconds, self.offset_seconds) }
    pub def since(earlier: DateTime) -> Duration { Duration { nanoseconds: self.unix_nanos() - earlier.unix_nanos() } }
    pub def __eq__(other: DateTime) -> Bool { self.unix_nanos() == other.unix_nanos() }
    pub def __lt__(other: DateTime) -> Bool { self.unix_nanos() < other.unix_nanos() }

    // RFC 3339; fractional seconds appear when nonzero.
    pub def to_string() -> String {
        var text = f"{self.year:04}-{self.month:02}-{self.day:02}T{self.hour:02}:{self.minute:02}:{self.second:02}";
        if self.nanosecond != 0 {
            var digits = f"{self.nanosecond:09}";
            while digits.ends_with("0") { digits = digits.substring(0, (digits.len() as i32) - 1); }
            text += "." + digits;
        }
        text + offset_text(self.offset_seconds, true)
    }
    // strftime-style: %Y year, %m month, %d day, %H hour, %M minute, %S second,
    // %f microseconds, %z offset (+0100), %j day of year, %a/%A weekday,
    // %b/%B month name, %% a percent sign.
    pub def format(pattern: String) -> String {
        let out = Vec<String>.new();
        let length = pattern.len() as i32;
        var index = 0;
        while index < length {
            let byte = pattern.byte_at(index);
            if byte != 37 || index + 1 >= length { out.push(pattern.substring(index, 1)); index += 1; continue; }
            let code = pattern.substring(index + 1, 1);
            index += 2;
            switch code {
                case "Y": out.push(f"{self.year:04}");
                case "m": out.push(f"{self.month:02}");
                case "d": out.push(f"{self.day:02}");
                case "H": out.push(f"{self.hour:02}");
                case "M": out.push(f"{self.minute:02}");
                case "S": out.push(f"{self.second:02}");
                case "f": out.push(f"{self.nanosecond / 1000:06}");
                case "z": out.push(offset_text(self.offset_seconds, false));
                case "j": out.push(f"{self.day_of_year():03}");
                case "a": out.push(weekday_name(self.weekday()).substring(0, 3));
                case "A": out.push(weekday_name(self.weekday()));
                case "b": out.push(month_name(self.month).substring(0, 3));
                case "B": out.push(month_name(self.month));
                case "%": out.push("%");
                default: out.push("%" + code);
            }
        }
        var text = "";
        for part in out { text += part; }
        text
    }
}

struct DateParser {
    let text: String;
    var at: i32;
    def take(expected: String) -> Bool {
        if self.at < (self.text.len() as i32) && self.text.substring(self.at, 1).equals(expected) { self.at += 1; return true; }
        false
    }
    def number(digits: i32) -> i32? {
        if self.at + digits > (self.text.len() as i32) { return nil; }
        var value = 0;
        for index in 0..<digits {
            let byte = self.text.byte_at(self.at + index);
            if !is_ascii_digit(byte) { return nil; }
            value = value * 10 + byte - 48;
        }
        self.at += digits;
        value
    }
}

def is_ascii_digit(byte: i32) -> Bool { byte >= 48 && byte <= 57 }

def offset_text(offset: i32, colon: Bool) -> String {
    if offset == 0 && colon { return "Z"; }
    var sign = "+"; var size = offset;
    if offset < 0 { sign = "-"; size = 0 - offset; }
    var separator = ""; if colon { separator = ":"; }
    f"{sign}{size / 3600:02}{separator}{(size % 3600) / 60:02}"
}

def floor_div(value: i64, divisor: i64) -> i64 {
    var quotient = value / divisor;
    if (value % divisor != 0) && ((value < 0) != (divisor < 0)) { quotient -= 1; }
    quotient
}

def is_leap_year(year: i32) -> Bool { (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 }

pub def days_in_month(year: i32, month: i32) -> i32 {
    switch month {
        case 2: return is_leap_year(year) ? 29 : 28;
        case 4, 6, 9, 11: return 30;
        default: return 31;
    }
}

// Days since 1970-01-01 (Howard Hinnant's algorithm).
def days_from_civil(year: i32, month: i32, day: i32) -> i64 {
    var y = year as i64;
    if month <= 2 { y -= 1; }
    let era = floor_div(y, 400);
    let year_of_era = y - era * 400;
    var shifted = (month as i64) - 3; if month <= 2 { shifted = (month as i64) + 9; }
    let day_of_year = (153 * shifted + 2) / 5 + (day as i64) - 1;
    let day_of_era = year_of_era * 365 + year_of_era / 4 - year_of_era / 100 + day_of_year;
    era * 146097 + day_of_era - 719468
}

def civil_from_days(days: i64) -> (i32, i32, i32) {
    let z = days + 719468;
    let era = floor_div(z, 146097);
    let day_of_era = z - era * 146097;
    let year_of_era = (day_of_era - day_of_era / 1460 + day_of_era / 36524 - day_of_era / 146096) / 365;
    let day_of_year = day_of_era - (365 * year_of_era + year_of_era / 4 - year_of_era / 100);
    let shifted = (5 * day_of_year + 2) / 153;
    let day = day_of_year - (153 * shifted + 2) / 5 + 1;
    var month = shifted + 3; if shifted >= 10 { month = shifted - 9; }
    var year = year_of_era + era * 400; if month <= 2 { year += 1; }
    (year as i32, month as i32, day as i32)
}

def weekday_name(day: i32) -> String {
    ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"][day - 1]
}

def month_name(month: i32) -> String {
    ["January", "February", "March", "April", "May", "June", "July", "August",
     "September", "October", "November", "December"][month - 1]
}

// ---- Time zones ----

pub struct TimeZoneError {
    pub let message: String;
    pub def to_string() -> String { self.message }
}

// One kind of local time: its UTC offset, whether it is daylight saving time, and its abbreviation.
struct ZoneType { let offset: i32; let dst: Bool; let abbreviation: String; }

// A day in a POSIX TZ rule: `Jn` (kind 0, Feb 29 never counted), `n` (kind 1,
// from 0) or `Mm.w.d` (kind 2: weekday d of week w, 5 meaning the last).
struct ZoneDate { let kind: i32; let number: i32; let month: i32; let week: i32; let weekday: i32; }

// The rule after the last listed transition, such as "CET-1CEST,M3.5.0,M10.5.0/3".
struct ZoneRule {
    let standard: ZoneType;
    let daylight: ZoneType?;
    let start: ZoneDate; let start_time: i32;
    let end: ZoneDate; let end_time: i32;
}

// A time zone from the IANA database (or a POSIX TZ rule): the UTC offset in
// effect at each moment, with daylight saving time and historical changes.
pub struct TimeZone {
    pub let name: String;
    let transitions: Vec<i64>;
    let indices: Vec<i32>;
    let types: Vec<ZoneType>;
    let rule: ZoneRule?;

    pub static def utc() -> TimeZone {
        TimeZone { name: "UTC", transitions: Vec<i64>.new(), indices: Vec<i32>.new(), types: [ZoneType { offset: 0, dst: false, abbreviation: "UTC" }], rule: nil }
    }

    // Loads a zone such as "America/New_York" from TZDIR or /usr/share/zoneinfo.
    pub static def load(name: String) -> Result<TimeZone, TimeZoneError> {
        if name.equals("UTC") || name.equals("Z") { return Result<TimeZone, TimeZoneError>.ok(value: TimeZone.utc()); }
        if !zone_name_valid(name) { return zone_error(f"invalid time zone name '{name}'"); }
        var directory = try_env_get("TZDIR") ?? "/usr/share/zoneinfo";
        if directory.len() == 0 { directory = "/usr/share/zoneinfo"; }
        guard let data = fs_read_text(directory + "/" + name, 1048576) else { return zone_error(f"unknown time zone '{name}'"); }
        TimeZone.from_tzif(name, data)
    }

    // The system's zone: TZ (a zone name, ":name", a file path or a POSIX
    // rule), else /etc/localtime, else UTC.
    pub static def local() -> TimeZone {
        if let setting = try_env_get("TZ") {
            var name = setting; if name.starts_with(":") { name = name.substring(1, (name.len() as i32) - 1); }
            if name.starts_with("/") { if let data = fs_read_text(name, 1048576) { if let zone = TimeZone.from_tzif(name, data).ok_value() { return zone; } } }
            else if name.len() > 0 {
                if let zone = TimeZone.load(name).ok_value() { return zone; }
                if let rule = parse_zone_rule(name) { return TimeZone { name, transitions: Vec<i64>.new(), indices: Vec<i32>.new(), types: [rule.standard], rule }; }
            }
        }
        if let data = fs_read_text("/etc/localtime", 1048576) { if let zone = TimeZone.from_tzif("localtime", data).ok_value() { return zone; } }
        TimeZone.utc()
    }

    // A zone from the bytes of a TZif file (RFC 8536).
    pub static def from_tzif(name: String, data: String) -> Result<TimeZone, TimeZoneError> {
        if data.len() < 44 || !data.substring(0, 4).equals("TZif") { return zone_error(f"{name} is not a TZif file"); }
        let version = data.byte_at(4);
        var at = 0;
        var wide = false;
        if version >= 50 {
            // Skip the 32-bit block: version 2 and later repeat the data with 64-bit times.
            at = 44 + tzif_block_size(data, 0, false);
            if (data.len() as i32) < at + 44 || !data.substring(at, 4).equals("TZif") { return zone_error(f"{name}: truncated TZif file"); }
            wide = true;
        }
        let isut = tzif_u32(data, at + 20); let isstd = tzif_u32(data, at + 24); let leap = tzif_u32(data, at + 28);
        let count = tzif_u32(data, at + 32); let type_count = tzif_u32(data, at + 36); let chars = tzif_u32(data, at + 40);
        var width = 4; if wide { width = 8; }
        if type_count == 0 || (data.len() as i32) < at + 44 + tzif_block_size(data, at, wide) { return zone_error(f"{name}: truncated TZif file"); }
        var cursor = at + 44;
        let transitions = Vec<i64>.new();
        for index in 0..<count {
            if wide { transitions.push(tzif_i64(data, cursor)); } else { transitions.push(tzif_u32(data, cursor) as i64); if transitions[index] >= 2147483648 { transitions[index] = transitions[index] - 4294967296; } }
            cursor += width;
        }
        let indices = Vec<i32>.new();
        for index in 0..<count {
            let kind = data.byte_at(cursor + index);
            if kind >= type_count { return zone_error(f"{name}: invalid transition type"); }
            indices.push(kind);
        }
        cursor += count;
        let abbreviations_at = cursor + type_count * 6;
        let types = Vec<ZoneType>.new();
        for index in 0..<type_count {
            var offset = tzif_u32(data, cursor) as i64; if offset >= 2147483648 { offset -= 4294967296; }
            let start = data.byte_at(cursor + 5);
            var end = start;
            while end < chars && data.byte_at(abbreviations_at + end) != 0 { end += 1; }
            types.push(ZoneType { offset: offset as i32, dst: data.byte_at(cursor + 4) != 0, abbreviation: data.substring(abbreviations_at + start, end - start) });
            cursor += 6;
        }
        cursor = abbreviations_at + chars + leap * (width + 4) + isstd + isut;
        var rule: ZoneRule? = nil;
        if wide && cursor < data.len() as i32 && data.byte_at(cursor) == 10 {
            let close = data.find_from("\n", cursor + 1);
            if close > cursor + 1 { rule = parse_zone_rule(data.substring(cursor + 1, close - cursor - 1)); }
        }
        Result<TimeZone, TimeZoneError>.ok(value: TimeZone { name, transitions, indices, types, rule })
    }

    // Seconds east of UTC at the instant `unix_seconds`.
    pub def offset_at(unix_seconds: i64) -> i32 { self.type_at(unix_seconds).offset }
    pub def abbreviation_at(unix_seconds: i64) -> String { self.type_at(unix_seconds).abbreviation }
    pub def is_dst_at(unix_seconds: i64) -> Bool { self.type_at(unix_seconds).dst }

    def type_at(unix_seconds: i64) -> ZoneType {
        let count = self.transitions.len() as i32;
        if count == 0 || unix_seconds >= self.transitions[count - 1] {
            if let rule = self.rule { return rule_type_at(rule, unix_seconds); }
            if count == 0 { return self.types[0]; }
            return self.types[self.indices[count - 1]];
        }
        if unix_seconds < self.transitions[0] { return self.types[0]; }
        // The last transition at or before the instant.
        var low = 0; var high = count - 1;
        while low < high {
            let middle = (low + high + 1) / 2;
            if self.transitions[middle] <= unix_seconds { low = middle; } else { high = middle - 1; }
        }
        self.types[self.indices[low]]
    }

    // The instant at a local date and time in this zone. A time skipped when
    // clocks go forward is read with the offset before the change (02:30 on
    // a spring-forward night becomes 03:30); a time that occurs twice when
    // clocks go back is the earlier one. Nil for an invalid date.
    pub def instant(year: i32, month: i32, day: i32, hour: i32 = 0, minute: i32 = 0, second: i32 = 0, nanosecond: i32 = 0) -> DateTime? {
        guard let wall = DateTime.from_parts(year, month, day, hour, minute, second, nanosecond) else { return nil; }
        let local = wall.unix_seconds();
        // Offsets in effect a day either side cover any change near this time.
        let before = self.offset_at(local - 86400);
        let after = self.offset_at(local + 86400);
        var chosen = before;
        if self.offset_at(local - (before as i64)) != before {
            if self.offset_at(local - (after as i64)) == after { chosen = after; }
        }
        DateTime.from_unix_nanos((local - (chosen as i64)) * 1000000000 + (nanosecond as i64), self.offset_at(local - (chosen as i64)))
    }
}

pub extension DateTime {
    // The same instant as local time in `zone`.
    pub def in_zone(zone: TimeZone) -> DateTime { self.with_offset(zone.offset_at(self.unix_seconds())) }
}

def zone_error(message: String) -> Result<TimeZone, TimeZoneError> {
    Result<TimeZone, TimeZoneError>.err(error: TimeZoneError { message })
}

// Names are paths below the zone directory: letters, digits, `_`, `-`, `+` and `/`, without `..`.
def zone_name_valid(name: String) -> Bool {
    if name.len() == 0 || name.len() > 128 || name.starts_with("/") || name.contains("..") { return false; }
    for index in 0..<(name.len() as i32) {
        let byte = name.byte_at(index);
        let ok = (byte >= 65 && byte <= 90) || (byte >= 97 && byte <= 122) || (byte >= 48 && byte <= 57) || byte == 95 || byte == 45 || byte == 43 || byte == 47;
        if !ok { return false; }
    }
    true
}

def tzif_u32(data: String, at: i32) -> i32 {
    // Counts and offsets fit in i32 for valid files; offsets are reinterpreted by callers.
    let value = ((data.byte_at(at) as i64) << 24) | ((data.byte_at(at + 1) as i64) << 16) | ((data.byte_at(at + 2) as i64) << 8) | (data.byte_at(at + 3) as i64);
    if value > 2147483647 { return (value - 4294967296) as i32; }
    value as i32
}

def tzif_i64(data: String, at: i32) -> i64 {
    var value: i64 = 0;
    for index in 0..<8 { value = (value << 8) | (data.byte_at(at + index) as i64); }
    value
}

// Bytes of the data block after the header at `at`.
def tzif_block_size(data: String, at: i32, wide: Bool) -> i32 {
    var width = 4; if wide { width = 8; }
    let isut = tzif_u32(data, at + 20); let isstd = tzif_u32(data, at + 24); let leap = tzif_u32(data, at + 28);
    let count = tzif_u32(data, at + 32); let types = tzif_u32(data, at + 36); let chars = tzif_u32(data, at + 40);
    if isut < 0 || isstd < 0 || leap < 0 || count < 0 || types < 0 || chars < 0 || count > 100000 || types > 256 || chars > 10000 || leap > 10000 { return 2147483647 - 44 - at; }
    count * width + count + types * 6 + chars + leap * (width + 4) + isstd + isut
}

// A POSIX TZ rule, e.g. "EST5EDT,M3.2.0,M11.1.0" or "<+08>-8"; nil when malformed.
def parse_zone_rule(text: String) -> ZoneRule? {
    let cursor = ZoneRuleCursor { text, at: 0 };
    guard let standard_name = cursor.name() else { return nil; }
    guard let standard_offset = cursor.offset() else { return nil; }
    let standard = ZoneType { offset: -standard_offset, dst: false, abbreviation: standard_name };
    let none = ZoneDate { kind: 1, number: 0, month: 0, week: 0, weekday: 0 };
    if cursor.done() { return ZoneRule { standard, daylight: nil, start: none, start_time: 0, end: none, end_time: 0 }; }
    guard let daylight_name = cursor.name() else { return nil; }
    var daylight_offset = standard_offset - 3600;
    if !cursor.done() && !cursor.peek(",") { guard let explicit = cursor.offset() else { return nil; } daylight_offset = explicit; }
    let daylight = ZoneType { offset: -daylight_offset, dst: true, abbreviation: daylight_name };
    // Without dates, the US rule of 1987-2006 is the POSIX default; zone files always give dates.
    if !cursor.take(",") { return nil; }
    guard let start = cursor.date() else { return nil; }
    var start_time = 7200; if cursor.take("/") { guard let time = cursor.offset() else { return nil; } start_time = time; }
    if !cursor.take(",") { return nil; }
    guard let end = cursor.date() else { return nil; }
    var end_time = 7200; if cursor.take("/") { guard let time = cursor.offset() else { return nil; } end_time = time; }
    if !cursor.done() { return nil; }
    ZoneRule { standard, daylight, start, start_time, end, end_time }
}

struct ZoneRuleCursor {
    let text: String;
    var at: i32;
    def done() -> Bool { self.at >= self.text.len() as i32 }
    def peek(token: String) -> Bool { !self.done() && self.text.substring(self.at, 1).equals(token) }
    def take(token: String) -> Bool { if self.peek(token) { self.at += 1; return true; } false }
    // An abbreviation: three or more letters, or `<...>` (which may hold digits and signs).
    def name() -> String? {
        if self.take("<") {
            let close = self.text.find_from(">", self.at);
            if close < 0 { return nil; }
            let value = self.text.substring(self.at, close - self.at);
            self.at = close + 1;
            return value;
        }
        let start = self.at;
        while !self.done() { let byte = self.text.byte_at(self.at); if (byte >= 65 && byte <= 90) || (byte >= 97 && byte <= 122) { self.at += 1; } else { break; } }
        if self.at - start < 3 { return nil; }
        self.text.substring(start, self.at - start)
    }
    def number() -> i32? {
        let start = self.at; var value = 0;
        while !self.done() && is_ascii_digit(self.text.byte_at(self.at)) && self.at - start < 4 { value = value * 10 + self.text.byte_at(self.at) - 48; self.at += 1; }
        if self.at == start { return nil; }
        value
    }
    // [+-]hh[:mm[:ss]] in seconds (POSIX offsets count west of UTC as positive).
    def offset() -> i32? {
        var sign = 1;
        if self.take("-") { sign = -1; } else { self.take("+"); }
        guard let hours = self.number() else { return nil; }
        var seconds = hours * 3600;
        if self.take(":") { guard let minutes = self.number() else { return nil; } seconds += minutes * 60;
            if self.take(":") { guard let extra = self.number() else { return nil; } seconds += extra; } }
        sign * seconds
    }
    def date() -> ZoneDate? {
        if self.take("J") { guard let day = self.number() else { return nil; } if day < 1 || day > 365 { return nil; } return ZoneDate { kind: 0, number: day, month: 0, week: 0, weekday: 0 }; }
        if self.take("M") {
            guard let month = self.number() else { return nil; }
            if !self.take(".") { return nil; }
            guard let week = self.number() else { return nil; }
            if !self.take(".") { return nil; }
            guard let weekday = self.number() else { return nil; }
            if month < 1 || month > 12 || week < 1 || week > 5 || weekday > 6 { return nil; }
            return ZoneDate { kind: 2, number: 0, month, week, weekday };
        }
        guard let day = self.number() else { return nil; }
        if day > 365 { return nil; }
        ZoneDate { kind: 1, number: day, month: 0, week: 0, weekday: 0 }
    }
}

// Days since 1970-01-01 of a rule date in `year`.
def zone_rule_day(date: ZoneDate, year: i32) -> i64 {
    let january = days_from_civil(year, 1, 1);
    if date.kind == 0 {
        var day = (date.number - 1) as i64;
        if is_leap_year(year) && date.number >= 60 { day += 1; }
        return january + day;
    }
    if date.kind == 1 { return january + (date.number as i64); }
    let first = days_from_civil(year, date.month, 1);
    // 1970-01-01 was a Thursday (weekday 4, counting Sunday as 0).
    let first_weekday = ((first % 7 + 7 + 4) % 7) as i32;
    var day = 1 + (date.weekday - first_weekday + 7) % 7 + (date.week - 1) * 7;
    while day > days_in_month(year, date.month) { day -= 7; }
    first + ((day - 1) as i64)
}

def rule_type_at(rule: ZoneRule, unix_seconds: i64) -> ZoneType {
    guard let daylight = rule.daylight else { return rule.standard; }
    let (year, month, day) = civil_from_days(floor_div(unix_seconds + (rule.standard.offset as i64), 86400));
    // Daylight time starts at a standard-time wall clock and ends at a daylight one.
    let start = zone_rule_day(rule.start, year) * 86400 + (rule.start_time as i64) - (rule.standard.offset as i64);
    let end = zone_rule_day(rule.end, year) * 86400 + (rule.end_time as i64) - (daylight.offset as i64);
    var in_daylight = false;
    if start < end { in_daylight = unix_seconds >= start && unix_seconds < end; }
    else { in_daylight = !(unix_seconds >= end && unix_seconds < start); }
    if in_daylight { return daylight; }
    rule.standard
}
