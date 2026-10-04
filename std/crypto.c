#include "../runtime/platform.h"
#include "crypto.h"
#include "../runtime/api.h"

/* std.crypto. Random bytes come from the operating system; digests, HMAC,
 * PBKDF2 and authenticated encryption come from OpenSSL's libcrypto, found
 * through the libssl that std.tls loads (see tls.c). Functions returning a
 * string handle return NULL on failure, with the reason in rt_crypto_failure. */

static char crypto_failure[256];

static void crypto_fail(const char* message) {
    snprintf(crypto_failure, sizeof(crypto_failure), "%s", message);
}

void* rt_crypto_failure(void) {
    size_t size = strlen(crypto_failure);
    char* copy = malloc(size + 1);
    if (!copy) rt_panic("crypto allocation failed");
    memcpy(copy, crypto_failure, size + 1);
    return rl_string_handle_from_value((StringVal){copy, (int64_t)size});
}

static void* crypto_bytes(const unsigned char* data, size_t size) {
    char* copy = malloc(size + 1);
    if (!copy) rt_panic("crypto allocation failed");
    if (size) memcpy(copy, data, size);
    copy[size] = 0;
    return rl_string_handle_from_value((StringVal){copy, (int64_t)size});
}

/* `count` bytes from the operating system's cryptographically secure source. */
void* rt_crypto_random_bytes(int32_t count) {
    if (count < 0) count = 0;
    unsigned char* data = malloc((size_t)count + 1);
    if (!data) rt_panic("crypto allocation failed");
#if defined(__APPLE__)
    arc4random_buf(data, (size_t)count);
#elif defined(__unix__)
    for (int32_t at = 0; at < count; at += 256) {
        size_t chunk = (size_t)(count - at < 256 ? count - at : 256);
        if (getentropy(data + at, chunk) != 0) rt_panic("the operating system's random source failed");
    }
#else
    rt_panic("no secure random source on this platform");
#endif
    void* result = crypto_bytes(data, (size_t)count);
    free(data);
    return result;
}

/* 1 when the strings are equal, taking time that depends only on their lengths. */
int32_t rt_crypto_equal(void* a, void* b) {
    StringVal x = rt_string_obj_value(a), y = rt_string_obj_value(b);
    if (x.len != y.len) return 0;
    unsigned char difference = 0;
    for (int64_t i = 0; i < x.len; i++) difference |= (unsigned char)(x.data[i] ^ y.data[i]);
    return difference == 0;
}

#if defined(__unix__) || defined(__APPLE__)

enum { CRYPTO_CTRL_AEAD_SET_IVLEN = 0x9, CRYPTO_CTRL_AEAD_GET_TAG = 0x10, CRYPTO_CTRL_AEAD_SET_TAG = 0x11 };

static struct {
    int state;
    const void* (*EVP_get_digestbyname)(const char*);
    const void* (*EVP_get_cipherbyname)(const char*);
    void* (*EVP_MD_CTX_new)(void);
    void (*EVP_MD_CTX_free)(void*);
    int (*EVP_DigestInit_ex)(void*, const void*, void*);
    int (*EVP_DigestUpdate)(void*, const void*, size_t);
    int (*EVP_DigestFinal_ex)(void*, unsigned char*, unsigned int*);
    unsigned char* (*HMAC)(const void*, const void*, int, const unsigned char*, size_t, unsigned char*, unsigned int*);
    int (*PKCS5_PBKDF2_HMAC)(const char*, int, const unsigned char*, int, int, const void*, int, unsigned char*);
    void* (*EVP_CIPHER_CTX_new)(void);
    void (*EVP_CIPHER_CTX_free)(void*);
    int (*EVP_CIPHER_CTX_ctrl)(void*, int, int, void*);
    int (*EVP_EncryptInit_ex)(void*, const void*, void*, const unsigned char*, const unsigned char*);
    int (*EVP_EncryptUpdate)(void*, unsigned char*, int*, const unsigned char*, int);
    int (*EVP_EncryptFinal_ex)(void*, unsigned char*, int*);
    int (*EVP_DecryptInit_ex)(void*, const void*, void*, const unsigned char*, const unsigned char*);
    int (*EVP_DecryptUpdate)(void*, unsigned char*, int*, const unsigned char*, int);
    int (*EVP_DecryptFinal_ex)(void*, unsigned char*, int*);
} crypto;

static int crypto_load(void) {
    if (crypto.state) return crypto.state > 0;
    if (!tls_load()) { crypto_fail(tls_failure); return 0; }
    crypto.state = -1;
#define CRYPTO_SYMBOL(name) \
    if (!(*(void**)&crypto.name = dlsym(tls.library, #name))) { crypto_fail("the OpenSSL library lacks " #name); return 0; }
    CRYPTO_SYMBOL(EVP_get_digestbyname) CRYPTO_SYMBOL(EVP_get_cipherbyname)
    CRYPTO_SYMBOL(EVP_MD_CTX_new) CRYPTO_SYMBOL(EVP_MD_CTX_free)
    CRYPTO_SYMBOL(EVP_DigestInit_ex) CRYPTO_SYMBOL(EVP_DigestUpdate) CRYPTO_SYMBOL(EVP_DigestFinal_ex)
    CRYPTO_SYMBOL(HMAC) CRYPTO_SYMBOL(PKCS5_PBKDF2_HMAC)
    CRYPTO_SYMBOL(EVP_CIPHER_CTX_new) CRYPTO_SYMBOL(EVP_CIPHER_CTX_free) CRYPTO_SYMBOL(EVP_CIPHER_CTX_ctrl)
    CRYPTO_SYMBOL(EVP_EncryptInit_ex) CRYPTO_SYMBOL(EVP_EncryptUpdate) CRYPTO_SYMBOL(EVP_EncryptFinal_ex)
    CRYPTO_SYMBOL(EVP_DecryptInit_ex) CRYPTO_SYMBOL(EVP_DecryptUpdate) CRYPTO_SYMBOL(EVP_DecryptFinal_ex)
#undef CRYPTO_SYMBOL
    crypto.state = 1;
    return 1;
}

static const void* crypto_digest(void* name_string) {
    if (!crypto_load()) return NULL;
    StringVal name = rt_string_obj_value(name_string);
    char text[64];
    if (name.len <= 0 || name.len >= (int64_t)sizeof(text)) { crypto_fail("unknown digest"); return NULL; }
    memcpy(text, name.data, (size_t)name.len); text[name.len] = 0;
    const void* md = crypto.EVP_get_digestbyname(text);
    if (!md) { snprintf(crypto_failure, sizeof(crypto_failure), "OpenSSL does not provide the digest %s", text); return NULL; }
    return md;
}

/* An incremental digest. Once finished, its OpenSSL context takes no more
 * calls: later updates are ignored and finishing again fails. */
typedef struct CryptoHasher { void* context; int finished; } CryptoHasher;

void* rt_crypto_hasher_new(void* name) {
    const void* md = crypto_digest(name);
    if (!md) return NULL;
    void* context = crypto.EVP_MD_CTX_new();
    if (!context || crypto.EVP_DigestInit_ex(context, md, NULL) != 1) {
        if (context) crypto.EVP_MD_CTX_free(context);
        crypto_fail("cannot start the digest"); return NULL;
    }
    CryptoHasher* hasher = malloc(sizeof(*hasher));
    if (!hasher) rt_panic("crypto allocation failed");
    hasher->context = context; hasher->finished = 0;
    return hasher;
}

/* 0 when the data was added, -1 after finish. */
int32_t rt_crypto_hasher_update(void* pointer, void* data) {
    CryptoHasher* hasher = pointer;
    if (!hasher || hasher->finished) return -1;
    StringVal value = rt_string_obj_value(data);
    if (value.len) crypto.EVP_DigestUpdate(hasher->context, value.data, (size_t)value.len);
    return 0;
}

/* The digest of everything added. */
void* rt_crypto_hasher_finish(void* pointer) {
    CryptoHasher* hasher = pointer;
    if (!hasher || hasher->finished) { crypto_fail("the hasher was already finished"); return NULL; }
    hasher->finished = 1;
    unsigned char digest[64]; unsigned int size = 0;
    if (crypto.EVP_DigestFinal_ex(hasher->context, digest, &size) != 1) { crypto_fail("cannot finish the digest"); return NULL; }
    return crypto_bytes(digest, size);
}

void rt_crypto_hasher_free(void* pointer) {
    CryptoHasher* hasher = pointer;
    if (!hasher) return;
    crypto.EVP_MD_CTX_free(hasher->context);
    free(hasher);
}

void* rt_crypto_hmac(void* name, void* key, void* data) {
    const void* md = crypto_digest(name);
    if (!md) return NULL;
    StringVal k = rt_string_obj_value(key), d = rt_string_obj_value(data);
    if (k.len > INT32_MAX) { crypto_fail("HMAC key too long"); return NULL; }
    unsigned char mac[64]; unsigned int size = 0;
    if (!crypto.HMAC(md, k.data ? k.data : "", (int)k.len, (const unsigned char*)(d.data ? d.data : ""), (size_t)d.len, mac, &size)) {
        crypto_fail("HMAC failed"); return NULL;
    }
    return crypto_bytes(mac, size);
}

void* rt_crypto_pbkdf2(void* name, void* password, void* salt, int32_t iterations, int32_t length) {
    const void* md = crypto_digest(name);
    if (!md) return NULL;
    StringVal p = rt_string_obj_value(password), s = rt_string_obj_value(salt);
    if (iterations < 1 || length < 1 || p.len > INT32_MAX || s.len > INT32_MAX) { crypto_fail("PBKDF2 needs positive iterations and length"); return NULL; }
    unsigned char* out = malloc((size_t)length);
    if (!out) rt_panic("crypto allocation failed");
    int ok = crypto.PKCS5_PBKDF2_HMAC(p.data ? p.data : "", (int)p.len, (const unsigned char*)(s.data ? s.data : ""), (int)s.len,
                                      iterations, md, length, out);
    void* result = ok == 1 ? crypto_bytes(out, (size_t)length) : NULL;
    if (ok != 1) crypto_fail("PBKDF2 failed");
    free(out);
    return result;
}

/* AEAD with a 12-byte nonce and a 16-byte tag appended to the ciphertext.
 * Only these ciphers are accepted: the code below relies on their AEAD
 * controls, stream output and key sizes. */
static const void* crypto_cipher(void* name_string, int64_t key_size, int64_t nonce_size) {
    if (!crypto_load()) return NULL;
    StringVal name = rt_string_obj_value(name_string);
    char text[64];
    if (name.len <= 0 || name.len >= (int64_t)sizeof(text)) { crypto_fail("unknown cipher"); return NULL; }
    memcpy(text, name.data, (size_t)name.len); text[name.len] = 0;
    int64_t wanted = 0;
    if (strcmp(text, "aes-128-gcm") == 0) wanted = 16;
    else if (strcmp(text, "aes-256-gcm") == 0 || strcmp(text, "chacha20-poly1305") == 0) wanted = 32;
    else { snprintf(crypto_failure, sizeof(crypto_failure), "unsupported cipher %s", text); return NULL; }
    if (key_size != wanted) { snprintf(crypto_failure, sizeof(crypto_failure), "%s needs a %lld-byte key", text, (long long)wanted); return NULL; }
    if (nonce_size != 12) { crypto_fail("the nonce must be 12 bytes"); return NULL; }
    const void* cipher = crypto.EVP_get_cipherbyname(text);
    if (!cipher) { snprintf(crypto_failure, sizeof(crypto_failure), "OpenSSL does not provide the cipher %s", text); return NULL; }
    return cipher;
}

void* rt_crypto_seal(void* name, void* key, void* nonce, void* plaintext, void* aad) {
    StringVal k = rt_string_obj_value(key), n = rt_string_obj_value(nonce), p = rt_string_obj_value(plaintext), a = rt_string_obj_value(aad);
    const void* cipher = crypto_cipher(name, k.len, n.len);
    if (!cipher) return NULL;
    if (p.len > INT32_MAX - 32 || a.len > INT32_MAX) { crypto_fail("message too long"); return NULL; }
    void* context = crypto.EVP_CIPHER_CTX_new();
    if (!context) rt_panic("crypto allocation failed");
    unsigned char* out = malloc((size_t)p.len + 16 + 16);
    if (!out) rt_panic("crypto allocation failed");
    int used = 0, more = 0, ok =
        crypto.EVP_EncryptInit_ex(context, cipher, NULL, NULL, NULL) == 1 &&
        crypto.EVP_CIPHER_CTX_ctrl(context, CRYPTO_CTRL_AEAD_SET_IVLEN, 12, NULL) == 1 &&
        crypto.EVP_EncryptInit_ex(context, NULL, NULL, (const unsigned char*)k.data, (const unsigned char*)n.data) == 1 &&
        (a.len == 0 || crypto.EVP_EncryptUpdate(context, NULL, &more, (const unsigned char*)a.data, (int)a.len) == 1) &&
        crypto.EVP_EncryptUpdate(context, out, &used, (const unsigned char*)(p.data ? p.data : ""), (int)p.len) == 1 &&
        crypto.EVP_EncryptFinal_ex(context, out + used, &more) == 1 &&
        crypto.EVP_CIPHER_CTX_ctrl(context, CRYPTO_CTRL_AEAD_GET_TAG, 16, out + used + more) == 1;
    crypto.EVP_CIPHER_CTX_free(context);
    void* result = ok ? crypto_bytes(out, (size_t)(used + more + 16)) : NULL;
    if (!ok) crypto_fail("encryption failed");
    free(out);
    return result;
}

/* NULL when the message was altered, or was sealed with another key, nonce or aad. */
void* rt_crypto_open(void* name, void* key, void* nonce, void* sealed, void* aad) {
    StringVal k = rt_string_obj_value(key), n = rt_string_obj_value(nonce), s = rt_string_obj_value(sealed), a = rt_string_obj_value(aad);
    const void* cipher = crypto_cipher(name, k.len, n.len);
    if (!cipher) return NULL;
    if (s.len < 16) { crypto_fail("the sealed message is shorter than its tag"); return NULL; }
    if (s.len > INT32_MAX || a.len > INT32_MAX) { crypto_fail("message too long"); return NULL; }
    int64_t length = s.len - 16;
    void* context = crypto.EVP_CIPHER_CTX_new();
    if (!context) rt_panic("crypto allocation failed");
    unsigned char* out = malloc((size_t)length + 16);
    if (!out) rt_panic("crypto allocation failed");
    unsigned char tag[16]; memcpy(tag, s.data + length, 16);
    int used = 0, more = 0, ok =
        crypto.EVP_DecryptInit_ex(context, cipher, NULL, NULL, NULL) == 1 &&
        crypto.EVP_CIPHER_CTX_ctrl(context, CRYPTO_CTRL_AEAD_SET_IVLEN, 12, NULL) == 1 &&
        crypto.EVP_DecryptInit_ex(context, NULL, NULL, (const unsigned char*)k.data, (const unsigned char*)n.data) == 1 &&
        (a.len == 0 || crypto.EVP_DecryptUpdate(context, NULL, &more, (const unsigned char*)a.data, (int)a.len) == 1) &&
        crypto.EVP_DecryptUpdate(context, out, &used, (const unsigned char*)(s.data ? s.data : ""), (int)length) == 1 &&
        crypto.EVP_CIPHER_CTX_ctrl(context, CRYPTO_CTRL_AEAD_SET_TAG, 16, tag) == 1 &&
        crypto.EVP_DecryptFinal_ex(context, out + used, &more) == 1;
    crypto.EVP_CIPHER_CTX_free(context);
    tls.ERR_clear_error();
    void* result = ok ? crypto_bytes(out, (size_t)(used + more)) : NULL;
    if (!ok) crypto_fail("the message failed authentication");
    free(out);
    return result;
}

#else

void* rt_crypto_hasher_new(void* name) { (void)name; crypto_fail("crypto is not supported on this platform"); return NULL; }
int32_t rt_crypto_hasher_update(void* context, void* data) { (void)context; (void)data; return -1; }
void* rt_crypto_hasher_finish(void* context) { (void)context; return NULL; }
void rt_crypto_hasher_free(void* context) { (void)context; }
void* rt_crypto_hmac(void* name, void* key, void* data) { (void)name; (void)key; (void)data; crypto_fail("crypto is not supported on this platform"); return NULL; }
void* rt_crypto_pbkdf2(void* name, void* password, void* salt, int32_t iterations, int32_t length) {
    (void)name; (void)password; (void)salt; (void)iterations; (void)length; crypto_fail("crypto is not supported on this platform"); return NULL;
}
void* rt_crypto_seal(void* name, void* key, void* nonce, void* plaintext, void* aad) {
    (void)name; (void)key; (void)nonce; (void)plaintext; (void)aad; crypto_fail("crypto is not supported on this platform"); return NULL;
}
void* rt_crypto_open(void* name, void* key, void* nonce, void* sealed, void* aad) {
    (void)name; (void)key; (void)nonce; (void)sealed; (void)aad; crypto_fail("crypto is not supported on this platform"); return NULL;
}

#endif
