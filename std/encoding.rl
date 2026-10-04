// Standard library: hex and base64 encodings of byte strings.
//
//     hex_encode("hi")              // "6869"
//     base64_encode("hello")        // "aGVsbG8="
//     base64_decode("aGVsbG8")      // "hello" (padding is optional)
import "string.rl"

pub extern "C" def rt_hex_encode(value: String, upper: i32) -> RawPtr;
pub extern "C" def rt_hex_decode(value: String) -> RawPtr;
pub extern "C" def rt_base64_encode(value: String, url: i32, padding: i32) -> RawPtr;
pub extern "C" def rt_base64_decode(value: String) -> RawPtr;

// Two hex digits per byte.
pub def hex_encode(bytes: String, upper: Bool = false) -> String {
    var flag = 0; if upper { flag = 1; }
    unsafe { return String.from_handle(rt_hex_encode(bytes, flag)); }
}
// The bytes of hex digits (either case); nil when malformed.
pub def hex_decode(text: String) -> String? {
    unsafe {
        let handle = rt_hex_decode(text);
        if (handle as i64) == 0 { return nil; }
        return String.from_handle(handle);
    }
}
// Base64 (RFC 4648); `url` uses the URL- and filename-safe alphabet.
pub def base64_encode(bytes: String, url: Bool = false, padding: Bool = true) -> String {
    var safe = 0; if url { safe = 1; }
    var padded = 0; if padding { padded = 1; }
    unsafe { return String.from_handle(rt_base64_encode(bytes, safe, padded)); }
}
// The bytes of base64 text in either alphabet, with or without padding; nil when malformed.
pub def base64_decode(text: String) -> String? {
    unsafe {
        let handle = rt_base64_decode(text);
        if (handle as i64) == 0 { return nil; }
        return String.from_handle(handle);
    }
}
