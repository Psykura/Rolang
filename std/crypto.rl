// Standard library: cryptographic hashes, message authentication, key
// derivation, authenticated encryption and secure random bytes.
//
//     let digest = hex_encode(hash(HashAlgorithm.sha256, "hello").ok_value() ?? "");
//     let tag = hmac(HashAlgorithm.sha256, key, message);
//     let key = random_bytes(32); let nonce = random_bytes(12);
//     let sealed = seal(Cipher.aes_256_gcm, key, nonce, "secret");
//
// Values are byte strings; std.encoding converts them to hex or base64.
// random_bytes and constant_time_equals use the operating system; the rest
// uses OpenSSL's libcrypto, loaded on first use as std.tls loads libssl, so
// those functions fail with a CryptoError where OpenSSL is not installed.
import "string.rl"
import "result.rl"

pub extern "C" def rt_crypto_failure() -> RawPtr;
pub extern "C" def rt_crypto_random_bytes(count: i32) -> RawPtr;
pub extern "C" def rt_crypto_equal(a: String, b: String) -> i32;
pub extern "C" def rt_crypto_hasher_new(name: String) -> RawPtr;
pub extern "C" def rt_crypto_hasher_update(context: RawPtr, data: String) -> i32;
pub extern "C" def rt_crypto_hasher_finish(context: RawPtr) -> RawPtr;
pub extern "C" def rt_crypto_hasher_free(context: RawPtr) -> Void;
pub extern "C" def rt_crypto_hmac(name: String, key: String, data: String) -> RawPtr;
pub extern "C" def rt_crypto_pbkdf2(name: String, password: String, salt: String, iterations: i32, length: i32) -> RawPtr;
pub extern "C" def rt_crypto_seal(name: String, key: String, nonce: String, plaintext: String, aad: String) -> RawPtr;
pub extern "C" def rt_crypto_open(name: String, key: String, nonce: String, sealed: String, aad: String) -> RawPtr;

pub struct CryptoError {
    pub let message: String;
    pub def to_string() -> String { self.message }
}

def crypto_result(handle: RawPtr) -> Result<String, CryptoError> {
    unsafe {
        if (handle as i64) == 0 { return Result<String, CryptoError>.err(error: CryptoError { message: String.from_handle(rt_crypto_failure()) }); }
        return Result<String, CryptoError>.ok(value: String.from_handle(handle));
    }
}

pub enum HashAlgorithm {
    case md5; case sha1; case sha224; case sha256; case sha384; case sha512;
    case sha3_256; case sha3_512; case blake2b512; case blake2s256;
    // OpenSSL's name for the algorithm.
    pub def name() -> String {
        switch self {
            case .md5: return "md5"; case .sha1: return "sha1"; case .sha224: return "sha224";
            case .sha256: return "sha256"; case .sha384: return "sha384"; case .sha512: return "sha512";
            case .sha3_256: return "sha3-256"; case .sha3_512: return "sha3-512";
            case .blake2b512: return "blake2b512"; case .blake2s256: return "blake2s256";
        }
    }
}

// Authenticated encryption: a 12-byte nonce, and a 16-byte tag appended to the ciphertext.
pub enum Cipher {
    case aes_128_gcm; case aes_256_gcm; case chacha20_poly1305;
    pub def name() -> String {
        switch self { case .aes_128_gcm: return "aes-128-gcm"; case .aes_256_gcm: return "aes-256-gcm"; case .chacha20_poly1305: return "chacha20-poly1305"; }
    }
    // Key length in bytes.
    pub def key_size() -> i32 { switch self { case .aes_128_gcm: return 16; default: return 32; } }
}

// `count` bytes from the operating system's secure random source, for keys,
// nonces, salts and tokens.
pub def random_bytes(count: i32) -> String {
    unsafe { return String.from_handle(rt_crypto_random_bytes(count)); }
}

// Whether two secrets are equal, in time that does not depend on where they differ.
pub def constant_time_equals(a: String, b: String) -> Bool {
    unsafe { return rt_crypto_equal(a, b) != 0; }
}

// The digest of `data`.
pub def hash(algorithm: HashAlgorithm, data: String) -> Result<String, CryptoError> {
    switch Hasher.new(algorithm) {
        case .ok(let hasher): hasher.update(data); return hasher.finish();
        case .err(let error): return Result<String, CryptoError>.err(error: error);
    }
}

// A digest computed over data added in pieces.
pub struct Hasher {
    var handle: RawPtr;
    pub static def new(algorithm: HashAlgorithm) -> Result<Hasher, CryptoError> {
        unsafe {
            let handle = rt_crypto_hasher_new(algorithm.name());
            if (handle as i64) == 0 { return Result<Hasher, CryptoError>.err(error: CryptoError { message: String.from_handle(rt_crypto_failure()) }); }
            return Result<Hasher, CryptoError>.ok(value: Hasher { handle });
        }
    }
    pub def __release__() -> Void {
        unsafe {
            let handle = self.handle;
            self.handle = 0 as RawPtr;
            rt_crypto_hasher_free(handle);
        }
    }
    // Adds data; ignored once the hasher is finished.
    pub def update(data: String) -> Hasher {
        unsafe { rt_crypto_hasher_update(self.handle, data); }
        self
    }
    // The digest; the hasher takes no more data afterwards, and finishing again fails.
    pub def finish() -> Result<String, CryptoError> {
        unsafe { return crypto_result(rt_crypto_hasher_finish(self.handle)); }
    }
}

// HMAC of `data` under `key`.
pub def hmac(algorithm: HashAlgorithm, key: String, data: String) -> Result<String, CryptoError> {
    unsafe { return crypto_result(rt_crypto_hmac(algorithm.name(), key, data)); }
}

// A `length`-byte key derived from a password (PBKDF2-HMAC). Use a random
// salt per password and as many iterations as the application can afford.
pub def pbkdf2(password: String, salt: String, iterations: i32, length: i32 = 32, algorithm: HashAlgorithm = HashAlgorithm.sha256) -> Result<String, CryptoError> {
    unsafe { return crypto_result(rt_crypto_pbkdf2(algorithm.name(), password, salt, iterations, length)); }
}

// Encrypts and authenticates `plaintext` (and authenticates `aad` without
// encrypting it). Never reuse a nonce with the same key.
pub def seal(cipher: Cipher, key: String, nonce: String, plaintext: String, aad: String = "") -> Result<String, CryptoError> {
    unsafe { return crypto_result(rt_crypto_seal(cipher.name(), key, nonce, plaintext, aad)); }
}

// Encrypts with a fresh random nonce, returned in front of the sealed message,
// so callers cannot reuse a nonce by mistake. Random 12-byte nonces are safe
// for about 2^32 messages under one key.
pub def encrypt(key: String, plaintext: String, aad: String = "", cipher: Cipher = Cipher.aes_256_gcm) -> Result<String, CryptoError> {
    let nonce = random_bytes(12);
    switch seal(cipher, key, nonce, plaintext, aad) {
        case .ok(let sealed): return Result<String, CryptoError>.ok(value: nonce + sealed);
        case .err(let error): return Result<String, CryptoError>.err(error: error);
    }
}

// Decrypts what encrypt() produced.
pub def decrypt(key: String, data: String, aad: String = "", cipher: Cipher = Cipher.aes_256_gcm) -> Result<String, CryptoError> {
    if data.len() < 28 { return Result<String, CryptoError>.err(error: CryptoError { message: "the encrypted message is too short" }); }
    open(cipher, key, data.substring(0, 12), data.substring(12, (data.len() as i32) - 12), aad)
}

// Decrypts a sealed message; fails when it was altered or sealed with another
// key, nonce or aad.
pub def open(cipher: Cipher, key: String, nonce: String, sealed: String, aad: String = "") -> Result<String, CryptoError> {
    unsafe { return crypto_result(rt_crypto_open(cipher.name(), key, nonce, sealed, aad)); }
}
