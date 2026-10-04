import std.io
import std.time
def main() -> i32 {
    guard let berlin = TimeZone.load("Europe/Berlin").ok_value() else { return 1; }
    guard let york = TimeZone.load("America/New_York").ok_value() else { return 1; }
    guard let shanghai = TimeZone.load("Asia/Shanghai").ok_value() else { return 1; }
    guard let instant = DateTime.parse("2026-07-01T12:00:00Z") else { return 1; }
    println(f"{instant.in_zone(berlin)} {instant.in_zone(york)} {instant.in_zone(shanghai)}");
    let unix = instant.unix_seconds();
    println(f"{berlin.abbreviation_at(unix)} {berlin.is_dst_at(unix)} {york.abbreviation_at(unix)} {shanghai.offset_at(unix)}");
    // Ordinary local times.
    println(f"{berlin.instant(2026, 1, 15, 9, 30)?.to_utc() ?? instant}");
    // 2026-03-29 02:30 does not exist in Berlin (clocks jump 02:00 -> 03:00).
    println(f"{berlin.instant(2026, 3, 29, 2, 30) ?? instant}");
    // 2026-10-25 02:30 happens twice in Berlin; the earlier one is chosen.
    println(f"{berlin.instant(2026, 10, 25, 2, 30) ?? instant}");
    // New York: 2026-11-01 01:30 twice, 2026-03-08 02:30 skipped.
    println(f"{york.instant(2026, 11, 1, 1, 30) ?? instant} {york.instant(2026, 3, 8, 2, 30) ?? instant}");
    // Far future dates use the zone's rule.
    println(f"{berlin.instant(2090, 7, 1, 12) ?? instant} {york.instant(2090, 1, 1) ?? instant}");
    println(f"{berlin.instant(2026, 2, 30) == nil}");
    for name in ["../etc/passwd", "Nowhere/City", "", "Europe/Berlin\0x"] {
        println(TimeZone.load(name).err_value()?.message ?? "loaded?");
    }
    println(f"{TimeZone.utc().offset_at(0)} {TimeZone.load("UTC").ok_value()?.name ?? "-"}");
    0
}
