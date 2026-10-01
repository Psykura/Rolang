// Byte-oriented SHA-256 primitives for files and strings, including NUL bytes.
import "string.rl"
pub extern "C" def rt_sha256_string_handle(value: String) -> RawPtr;
pub extern "C" def rt_sha256_file_handle(path: String) -> RawPtr;
pub def sha256(value: String) -> String {
    unsafe { return String.from_handle(rt_sha256_string_handle(value)); }
}
pub def file_sha256(path: String) -> String? {
    unsafe {
        let handle = rt_sha256_file_handle(path);
        if (handle as i64) == 0 { return nil; }
        return String.from_handle(handle);
    }
}
