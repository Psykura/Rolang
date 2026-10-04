// Standard library: gzip, zlib and raw deflate compression.
//
//     let packed = gzip("hello hello hello").ok_value() ?? "";
//     let text = gunzip(packed).ok_value() ?? "";
//     let data = decompress(body, CompressFormat.zlib, limit: 1048576);
//
// Uses the system's zlib, loaded on first use. Decompression stops with an
// error past `limit` bytes of output, so untrusted input cannot expand into
// gigabytes; the default limit is 256 MiB.
import "string.rl"
import "result.rl"

pub extern "C" def rt_compress_failure() -> RawPtr;
pub extern "C" def rt_compress(data: String, format: i32, level: i32) -> RawPtr;
pub extern "C" def rt_decompress(data: String, format: i32, limit: i64) -> RawPtr;
pub extern "C" def rt_crc32(data: String) -> i64;

pub struct CompressError {
    pub let message: String;
    pub def to_string() -> String { self.message }
}

pub enum CompressFormat {
    // gzip files and HTTP `Content-Encoding: gzip`.
    case gzip;
    // zlib streams (HTTP `Content-Encoding: deflate`).
    case zlib;
    // Deflate without a header, as inside zip files.
    case deflate;
    def code() -> i32 { switch self { case .gzip: return 0; case .zlib: return 1; case .deflate: return 2; } }
}

def compress_result(handle: RawPtr) -> Result<String, CompressError> {
    unsafe {
        if (handle as i64) == 0 { return Result<String, CompressError>.err(error: CompressError { message: String.from_handle(rt_compress_failure()) }); }
        return Result<String, CompressError>.ok(value: String.from_handle(handle));
    }
}

// Compresses at `level` 0 (store) to 9 (smallest); 6 balances speed and size.
pub def compress(data: String, format: CompressFormat = CompressFormat.gzip, level: i32 = 6) -> Result<String, CompressError> {
    unsafe { return compress_result(rt_compress(data, format.code(), level)); }
}

// Decompresses at most `limit` bytes of output.
pub def decompress(data: String, format: CompressFormat = CompressFormat.gzip, limit: i64 = 268435456) -> Result<String, CompressError> {
    unsafe { return compress_result(rt_decompress(data, format.code(), limit)); }
}

pub def gzip(data: String, level: i32 = 6) -> Result<String, CompressError> { compress(data, CompressFormat.gzip, level) }
pub def gunzip(data: String, limit: i64 = 268435456) -> Result<String, CompressError> { decompress(data, CompressFormat.gzip, limit) }

// CRC-32 of `data`, as used by gzip and zip; nil when zlib is unavailable.
pub def crc32(data: String) -> u32? {
    var value: i64 = 0;
    unsafe { value = rt_crc32(data); }
    if value < 0 { return nil; }
    value as u32
}
