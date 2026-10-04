#include "../runtime/platform.h"
#include "websocket.h"
#include "../runtime/api.h"

/* Byte-level helpers for WebSocket (RFC 6455) in std.http: SHA-1 for the
 * handshake (so plain ws:// needs no OpenSSL), frame headers and masking. */

static void* ws_bytes(const unsigned char* data, size_t size) {
    char* copy = malloc(size + 1);
    if (!copy) rt_panic("websocket allocation failed");
    if (size) memcpy(copy, data, size);
    copy[size] = 0;
    return rl_string_handle_from_value((StringVal){copy, (int64_t)size});
}

static uint32_t ws_rotate(uint32_t value, int bits) { return (value << bits) | (value >> (32 - bits)); }

/* SHA-1 of a string, as 20 raw bytes. */
void* rt_ws_sha1(void* input) {
    StringVal value = rt_string_obj_value(input);
    uint32_t h[5] = { 0x67452301, 0xEFCDAB89, 0x98BADCFE, 0x10325476, 0xC3D2E1F0 };
    uint64_t bits = (uint64_t)value.len * 8;
    size_t total = (size_t)value.len + 9;
    size_t padded = (total + 63) / 64 * 64;
    unsigned char* data = calloc(padded, 1);
    if (!data) rt_panic("websocket allocation failed");
    if (value.len) memcpy(data, value.data, (size_t)value.len);
    data[value.len] = 0x80;
    for (int i = 0; i < 8; i++) data[padded - 1 - i] = (unsigned char)(bits >> (8 * i));
    for (size_t block = 0; block < padded; block += 64) {
        uint32_t w[80];
        for (int i = 0; i < 16; i++) w[i] = (uint32_t)data[block + 4 * i] << 24 | (uint32_t)data[block + 4 * i + 1] << 16 | (uint32_t)data[block + 4 * i + 2] << 8 | data[block + 4 * i + 3];
        for (int i = 16; i < 80; i++) w[i] = ws_rotate(w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16], 1);
        uint32_t a = h[0], b = h[1], c = h[2], d = h[3], e = h[4];
        for (int i = 0; i < 80; i++) {
            uint32_t f, k;
            if (i < 20) { f = (b & c) | (~b & d); k = 0x5A827999; }
            else if (i < 40) { f = b ^ c ^ d; k = 0x6ED9EBA1; }
            else if (i < 60) { f = (b & c) | (b & d) | (c & d); k = 0x8F1BBCDC; }
            else { f = b ^ c ^ d; k = 0xCA62C1D6; }
            uint32_t next = ws_rotate(a, 5) + f + e + k + w[i];
            e = d; d = c; c = ws_rotate(b, 30); b = a; a = next;
        }
        h[0] += a; h[1] += b; h[2] += c; h[3] += d; h[4] += e;
    }
    free(data);
    unsigned char digest[20];
    for (int i = 0; i < 5; i++) { digest[4 * i] = (unsigned char)(h[i] >> 24); digest[4 * i + 1] = (unsigned char)(h[i] >> 16); digest[4 * i + 2] = (unsigned char)(h[i] >> 8); digest[4 * i + 3] = (unsigned char)h[i]; }
    return ws_bytes(digest, 20);
}

/* A frame: header for `opcode` (with FIN when `fin`), then the payload,
 * masked with the 4-byte `key` when it is not empty. */
void* rt_ws_frame(int32_t opcode, int32_t fin, void* payload_string, void* key_string) {
    StringVal payload = rt_string_obj_value(payload_string), key = rt_string_obj_value(key_string);
    int masked = key.len == 4;
    size_t header = 2 + (payload.len >= 65536 ? 8 : payload.len >= 126 ? 2 : 0) + (masked ? 4 : 0);
    size_t size = header + (size_t)payload.len;
    unsigned char* frame = malloc(size + 1);
    if (!frame) rt_panic("websocket allocation failed");
    frame[0] = (unsigned char)((fin ? 0x80 : 0) | (opcode & 0x0F));
    size_t at = 2;
    if (payload.len >= 65536) {
        frame[1] = 127;
        for (int i = 7; i >= 0; i--) frame[at++] = (unsigned char)((uint64_t)payload.len >> (8 * i));
    } else if (payload.len >= 126) {
        frame[1] = 126; frame[at++] = (unsigned char)(payload.len >> 8); frame[at++] = (unsigned char)payload.len;
    } else frame[1] = (unsigned char)payload.len;
    if (masked) { frame[1] |= 0x80; memcpy(frame + at, key.data, 4); at += 4; }
    for (int64_t i = 0; i < payload.len; i++) frame[at + (size_t)i] = (unsigned char)payload.data[i] ^ (masked ? (unsigned char)key.data[i & 3] : 0);
    frame[size] = 0;
    return rl_string_handle_from_value((StringVal){(char*)frame, (int64_t)size});
}

/* `data` XORed with the repeating 4-byte `key` (masking is its own inverse). */
void* rt_ws_mask(void* data_string, void* key_string) {
    StringVal data = rt_string_obj_value(data_string), key = rt_string_obj_value(key_string);
    unsigned char* out = malloc((size_t)data.len + 1);
    if (!out) rt_panic("websocket allocation failed");
    for (int64_t i = 0; i < data.len; i++) out[i] = (unsigned char)data.data[i] ^ (key.len == 4 ? (unsigned char)key.data[i & 3] : 0);
    out[data.len] = 0;
    return rl_string_handle_from_value((StringVal){(char*)out, data.len});
}

/* A 2-byte big-endian close code followed by the reason. */
void* rt_ws_close_payload(int32_t code, void* reason_string) {
    StringVal reason = rt_string_obj_value(reason_string);
    unsigned char* out = malloc((size_t)reason.len + 3);
    if (!out) rt_panic("websocket allocation failed");
    out[0] = (unsigned char)(code >> 8); out[1] = (unsigned char)code;
    if (reason.len) memcpy(out + 2, reason.data, (size_t)reason.len);
    out[reason.len + 2] = 0;
    return rl_string_handle_from_value((StringVal){(char*)out, reason.len + 2});
}
