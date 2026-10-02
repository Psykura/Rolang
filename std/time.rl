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
// not represented.
import "string.rl"
import "vec.rl"
import "range.rl"
import "task.rl"

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
