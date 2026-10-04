import std.io
import std.compress
import std.encoding
import std.subprocess
def main() async -> i32 {
    let text = "Rolang compresses text. ".repeat(1000);
    for format in [CompressFormat.gzip, CompressFormat.zlib, CompressFormat.deflate] {
        let packed = compress(text, format).ok_value() ?? "";
        let back = decompress(packed, format).ok_value() ?? "";
        println(f"{text.len()} -> {packed.len() < 300} {back.equals(text)}");
    }
    let level0 = compress(text, CompressFormat.gzip, 0).ok_value() ?? "";
    println(f"{level0.len() > text.len()} {compress(text, level: 12).err_value()?.message ?? "-"}");
    println(f"{crc32("123456789") ?? 0}");
    // Interoperates with the gzip tool.
    let tool = await shell("printf 'from gzip' | gzip -c | base64");
    let packed = base64_decode((tool.ok_value()?.stdout ?? "").trim()) ?? "";
    println(gunzip(packed).ok_value() ?? "?");
    // Two concatenated members.
    let both = (gzip("one ").ok_value() ?? "") + (gzip("two").ok_value() ?? "");
    println(gunzip(both).ok_value() ?? "?");
    // A bomb: 10 MB of zeros compress to about 10 KB, refused past the limit.
    let bomb = gzip("\0".repeat(10000000)).ok_value() ?? "";
    println(f"{bomb.len() < 20000} {gunzip(bomb, limit: 1000000).err_value()?.message ?? "-"}");
    println(f"{gunzip("not gzip").err_value()?.message ?? "-"}");
    println(f"{gunzip(packed.substring(0, 10)).err_value()?.message ?? "-"}");
    0
}
