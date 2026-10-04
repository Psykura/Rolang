#include "../runtime/platform.h"
#include "encoding.h"
#include "../runtime/api.h"

/* Hex and base64 for std.encoding. Decoders return NULL for malformed input. */

static void* encoding_result(char* data, int64_t size) {
    data[size] = 0;
    return rl_string_handle_from_value((StringVal){data, size});
}

static char* encoding_buffer(int64_t size) {
    char* data = malloc((size_t)size + 1);
    if (!data) rt_panic("encoding allocation failed");
    return data;
}

void* rt_hex_encode(void* string, int32_t upper) {
    StringVal value = rt_string_obj_value(string);
    const char* digits = upper ? "0123456789ABCDEF" : "0123456789abcdef";
    char* out = encoding_buffer(value.len * 2);
    for (int64_t i = 0; i < value.len; i++) {
        unsigned char byte = (unsigned char)value.data[i];
        out[2 * i] = digits[byte >> 4]; out[2 * i + 1] = digits[byte & 15];
    }
    return encoding_result(out, value.len * 2);
}

static int hex_value(unsigned char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

void* rt_hex_decode(void* string) {
    StringVal value = rt_string_obj_value(string);
    if (value.len % 2) return NULL;
    char* out = encoding_buffer(value.len / 2);
    for (int64_t i = 0; i < value.len / 2; i++) {
        int high = hex_value((unsigned char)value.data[2 * i]), low = hex_value((unsigned char)value.data[2 * i + 1]);
        if (high < 0 || low < 0) { free(out); return NULL; }
        out[i] = (char)(high * 16 + low);
    }
    return encoding_result(out, value.len / 2);
}

static const char BASE64_STANDARD[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
static const char BASE64_URL[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";

void* rt_base64_encode(void* string, int32_t url, int32_t padding) {
    StringVal value = rt_string_obj_value(string);
    const char* alphabet = url ? BASE64_URL : BASE64_STANDARD;
    char* out = encoding_buffer((value.len + 2) / 3 * 4);
    int64_t used = 0;
    const unsigned char* data = (const unsigned char*)value.data;
    for (int64_t i = 0; i < value.len; i += 3) {
        uint32_t chunk = (uint32_t)data[i] << 16;
        int64_t left = value.len - i;
        if (left > 1) chunk |= (uint32_t)data[i + 1] << 8;
        if (left > 2) chunk |= data[i + 2];
        out[used++] = alphabet[(chunk >> 18) & 63];
        out[used++] = alphabet[(chunk >> 12) & 63];
        if (left > 1) out[used++] = alphabet[(chunk >> 6) & 63]; else if (padding) out[used++] = '=';
        if (left > 2) out[used++] = alphabet[chunk & 63]; else if (padding) out[used++] = '=';
    }
    return encoding_result(out, used);
}

static int base64_value(unsigned char c) {
    if (c >= 'A' && c <= 'Z') return c - 'A';
    if (c >= 'a' && c <= 'z') return c - 'a' + 26;
    if (c >= '0' && c <= '9') return c - '0' + 52;
    if (c == '+' || c == '-') return 62;
    if (c == '/' || c == '_') return 63;
    return -1;
}

/* Accepts both alphabets, with or without padding; rejects other characters. */
void* rt_base64_decode(void* string) {
    StringVal value = rt_string_obj_value(string);
    int64_t length = value.len;
    while (length > 0 && value.data[length - 1] == '=') length--;
    if (value.len - length > 2 || length % 4 == 1) return NULL;
    char* out = encoding_buffer(length / 4 * 3 + 2);
    int64_t used = 0;
    uint32_t chunk = 0; int bits = 0;
    for (int64_t i = 0; i < length; i++) {
        int digit = base64_value((unsigned char)value.data[i]);
        if (digit < 0) { free(out); return NULL; }
        chunk = (chunk << 6) | (uint32_t)digit; bits += 6;
        if (bits >= 8) { bits -= 8; out[used++] = (char)((chunk >> bits) & 255); }
    }
    /* Leftover bits must be zero, so each input has one encoding. */
    if (bits > 0 && (chunk & ((1u << bits) - 1))) { free(out); return NULL; }
    return encoding_result(out, used);
}
