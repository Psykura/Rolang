import std.io
import std.time
def main() -> i32 {
    println(f"{Duration.millis(1500)} {Duration.micros(12345)} {Duration.nanos(800)} {Duration.seconds(125)} {Duration.minutes(90)} {-Duration.millis(3)} {Duration.from_seconds(0.25)}");
    println(f"{Duration.seconds(2).as_millis()} {Duration.millis(2500).whole_seconds()} {Duration.hours(1) > Duration.minutes(59)}");
    let epoch = DateTime.from_unix(0);
    println(f"{epoch} {epoch.weekday()} {epoch.day_of_year()}");
    guard let leap = DateTime.parse("2024-02-29T23:59:59.25+05:30") else { return 1; }
    println(f"{leap} {leap.to_utc()} {leap.unix_seconds()} {leap.weekday()} {leap.day_of_year()}");
    println(leap.format("%A %d %B %Y %H:%M:%S.%f %z %j %a %b %%"));
    println(f"{DateTime.from_unix(-31536001)} {DateTime.parse("2024-13-01T00:00:00Z") == nil} {DateTime.parse("1999-12-31 23:59:59z")?.to_string() ?? "?"}");
    println(f"{leap + Duration.hours(1)} {(leap + Duration.days(1)).since(leap)} {DateTime.from_parts(2023, 2, 29) == nil}");
    let start = Instant.now();
    sleep_blocking(Duration.millis(5));
    let spent = start.elapsed();
    println(f"{spent >= Duration.millis(5)} {DateTime.now().year >= 2024}");
    0
}
