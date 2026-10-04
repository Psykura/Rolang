import std.io
import std.crypto
import std.encoding
def main() -> i32 {
    println(f"{hex_encode("hi")} {hex_encode("\u{ff}\0", upper: true)} {hex_decode("6869") ?? "?"} {hex_decode("zz") == nil} {hex_decode("abc") == nil}");
    for text in ["", "f", "fo", "foo", "foob", "fooba", "foobar"] { print(f"{base64_encode(text)}|"); }
    println("");
    println(f"{base64_encode("\u{ff}\u{fe}", url: true, padding: false)} {base64_decode("Zm9vYg") ?? "?"} {base64_decode("Zm9vYg==") ?? "?"} {base64_decode("Zm9v!") == nil} {base64_decode("Zh==") == nil}");
    for algorithm in [HashAlgorithm.md5, HashAlgorithm.sha1, HashAlgorithm.sha256, HashAlgorithm.sha512, HashAlgorithm.sha3_256, HashAlgorithm.blake2s256] {
        println(f"{algorithm.name()} {hex_encode(hash(algorithm, "abc").ok_value() ?? "")}");
    }
    if let hasher = Hasher.new(HashAlgorithm.sha256).ok_value() { println(hex_encode(hasher.update("a").update("bc").finish().ok_value() ?? "")); }
    // RFC 4231 test case 2
    println(hex_encode(hmac(HashAlgorithm.sha256, "Jefe", "what do ya want for nothing?").ok_value() ?? ""));
    // RFC 6070 test (sha1, 2 iterations)
    println(hex_encode(pbkdf2("password", "salt", 2, 20, HashAlgorithm.sha1).ok_value() ?? ""));
    let key = random_bytes(32); let nonce = random_bytes(12);
    println(f"{key.len()} {key.equals(random_bytes(32))}");
    for cipher in [Cipher.aes_256_gcm, Cipher.chacha20_poly1305, Cipher.aes_128_gcm] {
        let k = random_bytes(cipher.key_size());
        switch seal(cipher, k, nonce, "attack at dawn", "header") {
            case .ok(let sealed):
                let back = open(cipher, k, nonce, sealed, "header").ok_value() ?? "?";
                let tampered = sealed.substring(0, 3) + "X" + sealed.substring(4, (sealed.len() as i32) - 4);
                let bad_aad = open(cipher, k, nonce, sealed, "other");
                println(f"{cipher.name()} {sealed.len()} {back} {open(cipher, k, nonce, tampered, "header").ok_value() == nil} {bad_aad.err_value()?.message ?? "-"}");
            case .err(let error): println(error.message);
        }
    }
    println(seal(Cipher.aes_256_gcm, "short", nonce, "x").err_value()?.message ?? "-");
    println(f"{constant_time_equals("abc", "abc")} {constant_time_equals("abc", "abd")} {constant_time_equals("abc", "ab")}");
    0
}
