import std.io
struct Point { var x: i32; def to_string() -> String { f"P({self.x})" } }
def main() -> i32 {
    let pi = 3.14159265;
    let n = 255;
    let name = "Rolang";
    println(f"[{pi:.2}] [{pi:8.3}] [{pi:<8.1}] [{pi:e}] [{0.256:.1%}] [{pi:+.0}]");
    println(f"[{n:x}] [{n:#X}] [{n:#b}] [{n:o}] [{n:08}] [{-n:+06}] [{n:>6}] [{n:^7}] [{n:*<6}]");
    println(f"[{name:10}] [{name:>10}] [{name:^10}] [{name:.3}] [{name:-^12}] [{"中文":>4}]");
    println(f"[{true:>6}] [{Point { x: 4 }:>8}] [{n > 3 ? 1 : 2}] [{[1, 2].len():03}]");
    let big: u64 = 18446744073709551615;
    println(f"{big:x} {(-9223372036854775807 - 1):x} {(7 as u8):08b}");
    println(f"{0.1 + 0.2} {1000.0} {1234567.0} {1e21} {0.0001} {1.2e-5} {2.0 / 3.0}");
    println(255.format("#x") + " " + 2.5.format(">6.2") + " " + "ab".format("*^6"));
    0
}
