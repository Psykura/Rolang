#include "../runtime/platform.h"
#include "fmt.h"
#include "../runtime/api.h"

/* ============================================================================
 * String Formatting
 * ============================================================================ */

// Replace first {} in fmt with the integer value, returns malloc'd string
void* rt_format_int(const char* fmt, int32_t val) {
    if (!fmt) return NULL;
    char buf[32];
    snprintf(buf, sizeof(buf), "%d", val);
    const char* pos = strstr(fmt, "{}");
    if (!pos) return strdup(fmt);
    size_t prefix_len = (size_t)(pos - fmt);
    size_t total = prefix_len + strlen(buf) + strlen(pos + 2) + 1;
    char* result = (char*)malloc(total);
    if (!result) return NULL;
    memcpy(result, fmt, prefix_len);
    memcpy(result + prefix_len, buf, strlen(buf));
    strcpy(result + prefix_len + strlen(buf), pos + 2);
    return result;
}

// Replace first {} in fmt with the i64 value
void* rt_format_i64(const char* fmt, int64_t val) {
    if (!fmt) return NULL;
    char buf[32];
    snprintf(buf, sizeof(buf), "%lld", (long long)val);
    const char* pos = strstr(fmt, "{}");
    if (!pos) return strdup(fmt);
    size_t prefix_len = (size_t)(pos - fmt);
    size_t total = prefix_len + strlen(buf) + strlen(pos + 2) + 1;
    char* result = (char*)malloc(total);
    if (!result) return NULL;
    memcpy(result, fmt, prefix_len);
    memcpy(result + prefix_len, buf, strlen(buf));
    strcpy(result + prefix_len + strlen(buf), pos + 2);
    return result;
}

// Replace first {} with string value (C string)
void* rt_format_str(const char* fmt, const char* val) {
    if (!fmt) return NULL;
    if (!val) val = "(null)";
    const char* pos = strstr(fmt, "{}");
    if (!pos) return strdup(fmt);
    size_t prefix_len = (size_t)(pos - fmt);
    size_t total = prefix_len + strlen(val) + strlen(pos + 2) + 1;
    char* result = (char*)malloc(total);
    if (!result) return NULL;
    memcpy(result, fmt, prefix_len);
    memcpy(result + prefix_len, val, strlen(val));
    strcpy(result + prefix_len + strlen(val), pos + 2);
    return result;
}

// StringVal wrappers for Rolang
StringVal rt_format_int_s(StringVal fmt, int32_t val) {
    StringVal sv = {NULL, 0};
    char* data = (char*)rt_format_int(fmt.data, val);
    if (!data) return sv;
    sv.data = data;
    sv.len = (int64_t)strlen(data);
    return sv;
}

StringVal rt_format_i64_s(StringVal fmt, int64_t val) {
    StringVal sv = {NULL, 0};
    char* data = (char*)rt_format_i64(fmt.data, val);
    if (!data) return sv;
    sv.data = data;
    sv.len = (int64_t)strlen(data);
    return sv;
}

StringVal rt_format_str_s(StringVal fmt, StringVal val) {
    StringVal sv = {NULL, 0};
    char* data = (char*)rt_format_str(fmt.data, val.data);
    if (!data) return sv;
    sv.data = data;
    sv.len = (int64_t)strlen(data);
    return sv;
}

/* Replace first {} in fmt with the f64 value (via %g formatting). */
StringVal rt_format_f64_s(StringVal fmt, double val) {
    StringVal sv = {NULL, 0};
    if (!fmt.data) return sv;
    char numbuf[32];
    int n = snprintf(numbuf, sizeof(numbuf), "%g", val);
    if (n < 0) return sv;
    /* Find first "{}" in fmt */
    int64_t pos = -1;
    for (int64_t i = 0; i + 1 < fmt.len; i++) {
        if (fmt.data[i] == '{' && fmt.data[i + 1] == '}') { pos = i; break; }
    }
    int64_t total;
    char* result;
    if (pos < 0) {
        /* No placeholder — return a copy of fmt */
        result = (char*)malloc((size_t)fmt.len + 1);
        if (!result) return sv;
        memcpy(result, fmt.data, (size_t)fmt.len);
        result[fmt.len] = '\0';
        sv.data = result;
        sv.len = fmt.len;
        return sv;
    }
    total = pos + (int64_t)n + (fmt.len - pos - 2);
    result = (char*)malloc((size_t)total + 1);
    if (!result) return sv;
    memcpy(result, fmt.data, (size_t)pos);
    memcpy(result + pos, numbuf, (size_t)n);
    memcpy(result + pos + n, fmt.data + pos + 2, (size_t)(fmt.len - pos - 2));
    result[total] = '\0';
    sv.data = result;
    sv.len = total;
    return sv;
}

/* Replace first {} in fmt with "true" or "false". */
StringVal rt_format_bool_s(StringVal fmt, int32_t val) {
    StringVal word;
    word.data = (val != 0) ? "true" : "false";
    word.len = (val != 0) ? 4 : 5;
    return rt_format_str_s(fmt, word);
}

void* rt_format_int_handle(void* fmt, int32_t val) {
    return rl_string_handle_from_value(rt_format_int_s(rt_string_obj_value(fmt), val));
}

void* rt_format_i64_handle(void* fmt, int64_t val) {
    return rl_string_handle_from_value(rt_format_i64_s(rt_string_obj_value(fmt), val));
}

void* rt_format_f64_handle(void* fmt, double val) {
    return rl_string_handle_from_value(rt_format_f64_s(rt_string_obj_value(fmt), val));
}

void* rt_format_bool_handle(void* fmt, int32_t val) {
    return rl_string_handle_from_value(rt_format_bool_s(rt_string_obj_value(fmt), val));
}

void* rt_format_str_handle(void* fmt, void* val) {
    return rl_string_handle_from_value(rt_format_str_s(
        rt_string_obj_value(fmt),
        rt_string_obj_value(val)
    ));
}

/* ============================================================================
 * Multi-argument formatting
 *
 * `rt_fmt_args` walks `fmt` looking for `{}` placeholders. Each placeholder
 * is filled by the next entry of the parallel `argv` / `kinds` arrays:
 *
 *     kinds[i] = 0  : argv[i].i is the integer value (i64)
 *     kinds[i] = 1  : argv[i].s is the StringVal value
 *     kinds[i] = 2  : argv[i].b is the Bool (0/1) value
 *     kinds[i] = 3  : argv[i].f is the f64 value
 *
 * Extra placeholders past `nargs` are kept as literal "{}".
 * Extra args past the last placeholder are silently dropped.
 *
 * The result is a freshly heap-allocated StringVal — caller owns the data.
 * ============================================================================ */

StringVal rt_fmt_args(StringVal fmt, int32_t nargs, const int32_t* kinds, const FmtArg* argv) {
    StringVal out = {NULL, 0};
    if (fmt.len == 0 || !fmt.data) {
        return out;
    }

    /* Estimate capacity: format length + 32 bytes per arg (i64 max ~20 chars,
     * doubles ~24 chars, bools 5). Strings need exact size. */
    size_t cap = (size_t)fmt.len + 1;
    for (int32_t i = 0; i < nargs; i++) {
        switch (kinds ? kinds[i] : -1) {
            case 1: cap += (size_t)argv[i].s.len; break;
            case 3: cap += 32; break;
            case 2: cap += 5; break;
            default: cap += 24; break;
        }
    }
    char* buf = (char*)malloc(cap + 1);
    if (!buf) return out;

    size_t bp = 0;
    int32_t arg_idx = 0;
    int64_t i = 0;
    while (i < fmt.len) {
        if (i + 1 < fmt.len && fmt.data[i] == '{' && fmt.data[i + 1] == '}') {
            if (kinds && argv && arg_idx < nargs) {
                char numbuf[32];
                int numlen = 0;
                switch (kinds[arg_idx]) {
                    case 0:
                        numlen = snprintf(numbuf, sizeof(numbuf), "%lld",
                                          (long long)argv[arg_idx].i);
                        if (numlen < 0) numlen = 0;
                        if ((size_t)numlen > cap - bp) numlen = (int)(cap - bp);
                        memcpy(buf + bp, numbuf, (size_t)numlen);
                        bp += (size_t)numlen;
                        break;
                    case 1: {
                        StringVal s = argv[arg_idx].s;
                        if (s.data && s.len > 0) {
                            size_t need = (size_t)s.len;
                            if (bp + need >= cap) {
                                size_t new_cap = (bp + need + 1) * 2;
                                char* nb = (char*)realloc(buf, new_cap + 1);
                                if (!nb) { free(buf); return out; }
                                buf = nb; cap = new_cap;
                            }
                            memcpy(buf + bp, s.data, need);
                            bp += need;
                        }
                        break;
                    }
                    case 2: {
                        const char* w = argv[arg_idx].b ? "true" : "false";
                        size_t need = strlen(w);
                        if (bp + need >= cap) {
                            size_t new_cap = (bp + need + 1) * 2;
                            char* nb = (char*)realloc(buf, new_cap + 1);
                            if (!nb) { free(buf); return out; }
                            buf = nb; cap = new_cap;
                        }
                        memcpy(buf + bp, w, need);
                        bp += need;
                        break;
                    }
                    case 3:
                        numlen = snprintf(numbuf, sizeof(numbuf), "%g", argv[arg_idx].f);
                        if (numlen < 0) numlen = 0;
                        if (bp + (size_t)numlen >= cap) {
                            size_t new_cap = (bp + (size_t)numlen + 1) * 2;
                            char* nb = (char*)realloc(buf, new_cap + 1);
                            if (!nb) { free(buf); return out; }
                            buf = nb; cap = new_cap;
                        }
                        memcpy(buf + bp, numbuf, (size_t)numlen);
                        bp += (size_t)numlen;
                        break;
                    default:
                        if (bp + 2 < cap) { buf[bp++] = '{'; buf[bp++] = '}'; }
                        break;
                }
                arg_idx++;
            } else {
                if (bp + 2 < cap) { buf[bp++] = '{'; buf[bp++] = '}'; }
            }
            i += 2;
        } else {
            if (bp + 1 >= cap) {
                size_t new_cap = (cap + 1) * 2;
                char* nb = (char*)realloc(buf, new_cap + 1);
                if (!nb) { free(buf); return out; }
                buf = nb; cap = new_cap;
            }
            buf[bp++] = fmt.data[i++];
        }
    }
    buf[bp] = '\0';
    out.data = buf;
    out.len = (int64_t)bp;
    return out;
}
