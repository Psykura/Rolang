// UTF-8 decoding and extended grapheme cluster segmentation (UAX #29).
#include "unicode.h"
#include "unicode_tables.h"

#define RL_REPLACEMENT 0xFFFD

/* Decodes the scalar at `at`, storing its byte width. Invalid or truncated
 * sequences, overlong forms, surrogates and values above U+10FFFF decode as
 * U+FFFD with width 1. */
static uint32_t rl_utf8_decode(const unsigned char* data, int64_t len, int64_t at, int32_t* width) {
    unsigned char lead = data[at];
    *width = 1;
    if (lead < 0x80) return lead;
    int32_t count; uint32_t scalar, minimum;
    if ((lead & 0xE0) == 0xC0) { count = 2; scalar = lead & 0x1F; minimum = 0x80; }
    else if ((lead & 0xF0) == 0xE0) { count = 3; scalar = lead & 0x0F; minimum = 0x800; }
    else if ((lead & 0xF8) == 0xF0) { count = 4; scalar = lead & 0x07; minimum = 0x10000; }
    else return RL_REPLACEMENT;
    if (at + count > len) return RL_REPLACEMENT;
    for (int32_t i = 1; i < count; i++) {
        unsigned char next = data[at + i];
        if ((next & 0xC0) != 0x80) return RL_REPLACEMENT;
        scalar = (scalar << 6) | (next & 0x3F);
    }
    if (scalar < minimum || scalar > 0x10FFFF || (scalar >= 0xD800 && scalar <= 0xDFFF)) return RL_REPLACEMENT;
    *width = count;
    return scalar;
}

static uint8_t rl_lookup(const RlUnicodeRange* table, size_t count, uint32_t scalar) {
    size_t low = 0, high = count;
    while (low < high) {
        size_t mid = low + (high - low) / 2;
        if (scalar < table[mid].lo) high = mid;
        else if (scalar > table[mid].hi) low = mid + 1;
        else return table[mid].value;
    }
    return 0;
}
#define RL_TABLE_LOOKUP(table, scalar) rl_lookup(table, sizeof(table) / sizeof(table[0]), scalar)

int32_t rt_string_scalar_at(void* s, int32_t offset) {
    StringVal text = rt_string_obj_value(s);
    if (offset < 0 || offset >= text.len) return -1;
    int32_t width;
    return (int32_t)rl_utf8_decode((const unsigned char*)text.data, text.len, offset, &width);
}

int32_t rt_string_scalar_width(void* s, int32_t offset) {
    StringVal text = rt_string_obj_value(s);
    if (offset < 0 || offset >= text.len) return 0;
    int32_t width;
    rl_utf8_decode((const unsigned char*)text.data, text.len, offset, &width);
    return width;
}

int32_t rt_string_is_valid_utf8(void* s) {
    StringVal text = rt_string_obj_value(s);
    const unsigned char* data = (const unsigned char*)text.data;
    for (int64_t at = 0; at < text.len;) {
        int32_t width;
        uint32_t scalar = rl_utf8_decode(data, text.len, at, &width);
        if (scalar == RL_REPLACEMENT && !(width == 3 && data[at] == 0xEF && data[at + 1] == 0xBF && data[at + 2] == 0xBD)) return 0;
        at += width;
    }
    return 1;
}

void* rt_string_from_scalar_handle(int32_t scalar) {
    uint32_t value = (uint32_t)scalar;
    if (scalar < 0 || value > 0x10FFFF || (value >= 0xD800 && value <= 0xDFFF)) value = RL_REPLACEMENT;
    char bytes[4]; int64_t len;
    if (value < 0x80) { bytes[0] = (char)value; len = 1; }
    else if (value < 0x800) { bytes[0] = (char)(0xC0 | (value >> 6)); bytes[1] = (char)(0x80 | (value & 0x3F)); len = 2; }
    else if (value < 0x10000) {
        bytes[0] = (char)(0xE0 | (value >> 12)); bytes[1] = (char)(0x80 | ((value >> 6) & 0x3F));
        bytes[2] = (char)(0x80 | (value & 0x3F)); len = 3;
    } else {
        bytes[0] = (char)(0xF0 | (value >> 18)); bytes[1] = (char)(0x80 | ((value >> 12) & 0x3F));
        bytes[2] = (char)(0x80 | ((value >> 6) & 0x3F)); bytes[3] = (char)(0x80 | (value & 0x3F)); len = 4;
    }
    return rt_string_from_rodata(bytes, len);
}

static int rl_is_control(uint8_t gcb) { return gcb == RL_GCB_CR || gcb == RL_GCB_LF || gcb == RL_GCB_CONTROL; }

/* Byte offset just past the extended grapheme cluster that starts at `offset`. */
int32_t rt_string_grapheme_end(void* s, int32_t offset) {
    StringVal text = rt_string_obj_value(s);
    const unsigned char* data = (const unsigned char*)text.data;
    if (offset < 0 || offset >= text.len) return offset;
    int32_t width;
    uint32_t scalar = rl_utf8_decode(data, text.len, offset, &width);
    uint8_t previous = RL_TABLE_LOOKUP(rl_grapheme_break, scalar);
    /* GB11: after Extended_Pictographic Extend*, a ZWJ may join the next pictograph. */
    enum { EMOJI_NONE, EMOJI_PICT, EMOJI_PICT_ZWJ } emoji = RL_TABLE_LOOKUP(rl_extended_pictographic, scalar) ? EMOJI_PICT : EMOJI_NONE;
    /* GB9c: Consonant [Extend Linker]* Linker [Extend Linker]* joins a Consonant. */
    enum { CONJUNCT_NONE, CONJUNCT_CONSONANT, CONJUNCT_LINKED } conjunct = RL_TABLE_LOOKUP(rl_indic_conjunct_break, scalar) == RL_INCB_CONSONANT ? CONJUNCT_CONSONANT : CONJUNCT_NONE;
    int32_t regional = previous == RL_GCB_REGIONAL_INDICATOR ? 1 : 0;
    int64_t at = offset + width;
    while (at < text.len) {
        scalar = rl_utf8_decode(data, text.len, at, &width);
        uint8_t current = RL_TABLE_LOOKUP(rl_grapheme_break, scalar);
        int pictographic = RL_TABLE_LOOKUP(rl_extended_pictographic, scalar) != 0;
        uint8_t incb = RL_TABLE_LOOKUP(rl_indic_conjunct_break, scalar);
        int join;
        if (previous == RL_GCB_CR && current == RL_GCB_LF) join = 1;                                   /* GB3 */
        else if (rl_is_control(previous) || rl_is_control(current)) join = 0;                         /* GB4, GB5 */
        else if (previous == RL_GCB_L && (current == RL_GCB_L || current == RL_GCB_V || current == RL_GCB_LV || current == RL_GCB_LVT)) join = 1; /* GB6 */
        else if ((previous == RL_GCB_LV || previous == RL_GCB_V) && (current == RL_GCB_V || current == RL_GCB_T)) join = 1; /* GB7 */
        else if ((previous == RL_GCB_LVT || previous == RL_GCB_T) && current == RL_GCB_T) join = 1;  /* GB8 */
        else if (current == RL_GCB_EXTEND || current == RL_GCB_ZWJ || current == RL_GCB_SPACINGMARK) join = 1; /* GB9, GB9a */
        else if (previous == RL_GCB_PREPEND) join = 1;                                                 /* GB9b */
        else if (incb == RL_INCB_CONSONANT && conjunct == CONJUNCT_LINKED) join = 1;                  /* GB9c */
        else if (pictographic && emoji == EMOJI_PICT_ZWJ) join = 1;                                    /* GB11 */
        else if (previous == RL_GCB_REGIONAL_INDICATOR && current == RL_GCB_REGIONAL_INDICATOR) join = regional % 2 == 1; /* GB12, GB13 */
        else join = 0;                                                                                 /* GB999 */
        if (!join) break;
        if (pictographic) emoji = EMOJI_PICT;
        else if (current == RL_GCB_EXTEND && emoji == EMOJI_PICT) emoji = EMOJI_PICT;
        else if (current == RL_GCB_ZWJ && emoji == EMOJI_PICT) emoji = EMOJI_PICT_ZWJ;
        else emoji = EMOJI_NONE;
        if (incb == RL_INCB_CONSONANT) conjunct = CONJUNCT_CONSONANT;
        else if (incb == RL_INCB_LINKER && conjunct != CONJUNCT_NONE) conjunct = CONJUNCT_LINKED;
        else if (incb == RL_INCB_EXTEND && conjunct != CONJUNCT_NONE) { /* keeps the conjunct state */ }
        else conjunct = CONJUNCT_NONE;
        regional = current == RL_GCB_REGIONAL_INDICATOR ? regional + 1 : 0;
        previous = current;
        at += width;
    }
    return (int32_t)at;
}
