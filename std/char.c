#include "../runtime/platform.h"
#include "char.h"
#include "../runtime/api.h"

/* ============================================================================
 * Character classification
 * ============================================================================ */

int32_t rt_char_is_digit(int32_t ch) {
    return (ch >= '0' && ch <= '9') ? 1 : 0;
}

int32_t rt_char_is_alpha(int32_t ch) {
    return ((ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z')) ? 1 : 0;
}

int32_t rt_char_is_alnum(int32_t ch) {
    return ((ch >= '0' && ch <= '9') || (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z')) ? 1 : 0;
}

int32_t rt_char_is_space(int32_t ch) {
    return (ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r') ? 1 : 0;
}
