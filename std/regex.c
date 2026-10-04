#include "../runtime/platform.h"
#include "regex.h"
#include "../runtime/api.h"

/* Regular expressions for std.regex: a parser producing a syntax tree, a
 * compiler to a small instruction set, and a Pike VM that runs every thread
 * in lockstep, so matching takes time linear in the text for any pattern (no
 * catastrophic backtracking). Matches are leftmost-first, as in Perl, RE2 and
 * Rust's regex. Text is UTF-8: `.` and classes match one code point, and
 * positions are byte offsets. */

enum { RX_CHAR, RX_ANY, RX_ANY_NL, RX_CLASS, RX_MATCH, RX_JMP, RX_SPLIT, RX_SAVE, RX_ASSERT, RX_LOOP };
enum { RX_BOL, RX_EOL, RX_BOT, RX_EOT, RX_WORD, RX_NOT_WORD };
enum { RX_IGNORE_CASE = 1, RX_MULTILINE = 2, RX_DOT_ALL = 4 };
#define RX_MAX_PROGRAM 50000
#define RX_MAX_REPEAT 1000

typedef struct { int32_t op, x, y; } RxInst;
typedef struct { int32_t lo, hi; } RxRange;
typedef struct { RxRange* ranges; int32_t count, capacity, negated; } RxClass;

/* Syntax tree. */
enum { RN_EMPTY, RN_CHAR, RN_ANY, RN_CLASS, RN_CONCAT, RN_ALT, RN_REPEAT, RN_GROUP, RN_ASSERT };
typedef struct RxNode {
    int32_t kind, value, min, max, greedy, flags;
    struct RxNode** children; int32_t count, capacity;
} RxNode;

typedef struct Regex {
    RxInst* code; int32_t length, capacity;
    RxClass* classes; int32_t class_count, class_capacity;
    int32_t groups;          /* capturing groups, not counting the whole match */
    int32_t loops;           /* unbounded repetitions, each with a slot for its iteration start */
    char** names;            /* names[i] for group i (1-based), or NULL */
    int64_t* captures;       /* the last match: start/end byte offsets per group, -1 when unset */
} Regex;

typedef struct {
    const unsigned char* pattern; int64_t length, at;
    Regex* re; int32_t flags;
    char error[200];
    RxNode** nodes; int32_t node_count, node_capacity;
} RxParser;

static char regex_failure[256];

void* rt_regex_failure(void) {
    size_t size = strlen(regex_failure);
    char* copy = malloc(size + 1);
    if (!copy) rt_panic("regex allocation failed");
    memcpy(copy, regex_failure, size + 1);
    return rl_string_handle_from_value((StringVal){copy, (int64_t)size});
}

static void* rx_alloc(size_t size) {
    void* data = calloc(1, size ? size : 1);
    if (!data) rt_panic("regex allocation failed");
    return data;
}
static void* rx_grow(void* data, int32_t* capacity, int32_t needed, size_t item) {
    if (needed <= *capacity) return data;
    int32_t next = *capacity ? *capacity * 2 : 8;
    while (next < needed) next *= 2;
    void* grown = realloc(data, (size_t)next * item);
    if (!grown) rt_panic("regex allocation failed");
    *capacity = next;
    return grown;
}

/* One UTF-8 code point at `text[at]`; invalid bytes decode as themselves (one byte). */
static int32_t rx_decode(const unsigned char* text, int64_t length, int64_t at, int32_t* size) {
    unsigned char first = text[at];
    if (first < 0x80) { *size = 1; return first; }
    int32_t count = first >= 0xF0 ? 4 : first >= 0xE0 ? 3 : first >= 0xC0 ? 2 : 0;
    if (count == 0 || at + count > length) { *size = 1; return first; }
    int32_t value = first & (0x7F >> count);
    for (int32_t i = 1; i < count; i++) {
        unsigned char next = text[at + i];
        if ((next & 0xC0) != 0x80) { *size = 1; return first; }
        value = (value << 6) | (next & 0x3F);
    }
    *size = count;
    return value;
}

/* ---- Parser ---- */

static RxNode* rx_node(RxParser* p, int32_t kind) {
    RxNode* node = rx_alloc(sizeof(RxNode));
    node->kind = kind; node->greedy = 1; node->flags = p->flags;
    p->nodes = rx_grow(p->nodes, &p->node_capacity, p->node_count + 1, sizeof(RxNode*));
    p->nodes[p->node_count++] = node;
    return node;
}
static void rx_add_child(RxNode* parent, RxNode* child) {
    parent->children = rx_grow(parent->children, &parent->capacity, parent->count + 1, sizeof(RxNode*));
    parent->children[parent->count++] = child;
}
static int rx_fail(RxParser* p, const char* message) {
    if (!p->error[0]) snprintf(p->error, sizeof(p->error), "%s at offset %lld", message, (long long)p->at);
    return 0;
}
static int rx_peek(RxParser* p) { return p->at < p->length ? p->pattern[p->at] : -1; }

static int32_t rx_new_class(Regex* re) {
    re->classes = rx_grow(re->classes, &re->class_capacity, re->class_count + 1, sizeof(RxClass));
    memset(&re->classes[re->class_count], 0, sizeof(RxClass));
    return re->class_count++;
}
static void rx_class_add(RxClass* c, int32_t lo, int32_t hi) {
    c->ranges = rx_grow(c->ranges, &c->capacity, c->count + 1, sizeof(RxRange));
    c->ranges[c->count].lo = lo; c->ranges[c->count].hi = hi; c->count++;
}
/* With ignore-case, ASCII letters in the ranges also match the other case. */
static void rx_class_fold(RxClass* c) {
    int32_t count = c->count;
    for (int32_t i = 0; i < count; i++) {
        int32_t lo = c->ranges[i].lo, hi = c->ranges[i].hi;
        int32_t a = lo < 'a' ? 'a' : lo, b = hi > 'z' ? 'z' : hi;
        if (a <= b) rx_class_add(c, a - 32, b - 32);
        a = lo < 'A' ? 'A' : lo; b = hi > 'Z' ? 'Z' : hi;
        if (a <= b) rx_class_add(c, a + 32, b + 32);
    }
}
static void rx_class_digit(RxClass* c) { rx_class_add(c, '0', '9'); }
static void rx_class_word(RxClass* c) { rx_class_add(c, '0', '9'); rx_class_add(c, 'A', 'Z'); rx_class_add(c, '_', '_'); rx_class_add(c, 'a', 'z'); }
static void rx_class_space(RxClass* c) { rx_class_add(c, '\t', '\r'); rx_class_add(c, ' ', ' '); }
/* The complement of a class's ranges, for \D, \W and \S inside brackets. */
static void rx_class_add_negated(RxClass* c, RxClass* source) {
    int32_t next = 0;
    for (int32_t value = 0; value <= 0x10FFFF;) {
        int32_t covered = 0;
        for (int32_t i = 0; i < source->count; i++) if (value >= source->ranges[i].lo && value <= source->ranges[i].hi) { covered = 1; value = source->ranges[i].hi + 1; break; }
        if (covered) continue;
        int32_t end = 0x10FFFF;
        for (int32_t i = 0; i < source->count; i++) if (source->ranges[i].lo > value && source->ranges[i].lo - 1 < end) end = source->ranges[i].lo - 1;
        rx_class_add(c, value, end);
        value = end + 1;
        (void)next;
    }
}

static int32_t rx_hex(RxParser* p, int32_t digits_max, int braces) {
    int32_t value = 0, digits = 0;
    while (digits < digits_max) {
        int c = rx_peek(p);
        int d = c >= '0' && c <= '9' ? c - '0' : c >= 'a' && c <= 'f' ? c - 'a' + 10 : c >= 'A' && c <= 'F' ? c - 'A' + 10 : -1;
        if (d < 0) break;
        value = value * 16 + d; digits++; p->at++;
        if (value > 0x10FFFF) { rx_fail(p, "code point out of range"); return -1; }
    }
    if (digits == 0 || (!braces && digits != digits_max)) { rx_fail(p, "invalid hex escape"); return -1; }
    return value;
}

/* An escape after `\`: a code point (returned), or a class added to `out` (returns -2). */
static int32_t rx_escape(RxParser* p, RxClass* out, int in_class, int32_t* assertion) {
    if (p->at >= p->length) { rx_fail(p, "trailing backslash"); return -1; }
    int c = p->pattern[p->at++];
    RxClass temporary; memset(&temporary, 0, sizeof(temporary));
    switch (c) {
        case 'n': return '\n'; case 't': return '\t'; case 'r': return '\r';
        case 'f': return '\f'; case 'v': return '\v'; case '0': return 0;
        case 'x':
            if (rx_peek(p) == '{') { p->at++; int32_t v = rx_hex(p, 6, 1); if (v < 0) return -1; if (rx_peek(p) != '}') { rx_fail(p, "unclosed \\x{"); return -1; } p->at++; return v; }
            return rx_hex(p, 2, 0);
        case 'd': rx_class_digit(out); return -2;
        case 'w': rx_class_word(out); return -2;
        case 's': rx_class_space(out); return -2;
        case 'D': rx_class_digit(&temporary); rx_class_add_negated(out, &temporary); free(temporary.ranges); return -2;
        case 'W': rx_class_word(&temporary); rx_class_add_negated(out, &temporary); free(temporary.ranges); return -2;
        case 'S': rx_class_space(&temporary); rx_class_add_negated(out, &temporary); free(temporary.ranges); return -2;
        case 'b': if (in_class) return '\b'; *assertion = RX_WORD; return -3;
        case 'B': if (!in_class) { *assertion = RX_NOT_WORD; return -3; } break;
        case 'A': if (!in_class) { *assertion = RX_BOT; return -3; } break;
        case 'z': if (!in_class) { *assertion = RX_EOT; return -3; } break;
        default: break;
    }
    if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')) { p->at--; rx_fail(p, "unknown escape"); return -1; }
    /* Punctuation escapes to itself; other bytes start a UTF-8 code point. */
    p->at--;
    int32_t size = 1;
    int32_t value = rx_decode(p->pattern, p->length, p->at, &size);
    p->at += size;
    return value;
}

static RxNode* rx_alternation(RxParser* p);

static RxNode* rx_class_node(RxParser* p) {
    /* After '[' */
    int32_t index = rx_new_class(p->re);
    RxClass* c = &p->re->classes[index];
    if (rx_peek(p) == '^') { c->negated = 1; p->at++; }
    int first = 1;
    while (1) {
        if (p->at >= p->length) { rx_fail(p, "unclosed character class"); return NULL; }
        int ch = p->pattern[p->at];
        if (ch == ']' && !first) { p->at++; break; }
        first = 0;
        int32_t lo;
        if (ch == '\\') {
            p->at++;
            int32_t assertion = 0;
            c = &p->re->classes[index];
            lo = rx_escape(p, c, 1, &assertion);
            if (lo == -1) return NULL;
            if (lo == -2) continue;
        } else {
            int32_t size = 1; lo = rx_decode(p->pattern, p->length, p->at, &size); p->at += size;
        }
        int32_t hi = lo;
        if (rx_peek(p) == '-' && p->at + 1 < p->length && p->pattern[p->at + 1] != ']') {
            p->at++;
            if (rx_peek(p) == '\\') {
                p->at++; int32_t assertion = 0;
                c = &p->re->classes[index];
                hi = rx_escape(p, c, 1, &assertion);
                if (hi == -1) return NULL;
                if (hi == -2) { rx_fail(p, "invalid range end"); return NULL; }
            } else { int32_t size = 1; hi = rx_decode(p->pattern, p->length, p->at, &size); p->at += size; }
            if (hi < lo) { rx_fail(p, "invalid range: end before start"); return NULL; }
        }
        c = &p->re->classes[index];
        rx_class_add(c, lo, hi);
    }
    c = &p->re->classes[index];
    if (p->flags & RX_IGNORE_CASE) rx_class_fold(c);
    RxNode* node = rx_node(p, RN_CLASS); node->value = index;
    return node;
}

/* `(?flags)` or `(?flags:` after "(?"; returns 1 for a group with a body. */
static int rx_flags(RxParser* p, int32_t* flags) {
    int on = 1;
    while (p->at < p->length) {
        int c = p->pattern[p->at++];
        int32_t bit = c == 'i' ? RX_IGNORE_CASE : c == 'm' ? RX_MULTILINE : c == 's' ? RX_DOT_ALL : 0;
        if (c == '-') { on = 0; continue; }
        if (c == ')') return 0;
        if (c == ':') return 1;
        if (!bit) { p->at--; return rx_fail(p, "unknown group flag") - 1; }
        if (on) *flags |= bit; else *flags &= ~bit;
    }
    return rx_fail(p, "unclosed group") - 1;
}

static RxNode* rx_atom(RxParser* p) {
    int c = p->pattern[p->at];
    if (c == '(') {
        p->at++;
        int32_t group = -1;
        int32_t saved = p->flags;
        if (rx_peek(p) == '?') {
            p->at++;
            int c2 = rx_peek(p);
            if (c2 == ':') p->at++;
            else if (c2 == '<' || c2 == 'P') {
                if (c2 == 'P') { p->at++; if (rx_peek(p) != '<') { rx_fail(p, "expected (?P<name>"); return NULL; } }
                p->at++;
                int64_t start = p->at;
                while (p->at < p->length && (isalnum(p->pattern[p->at]) || p->pattern[p->at] == '_')) p->at++;
                if (p->at == start || rx_peek(p) != '>') { rx_fail(p, "invalid group name"); return NULL; }
                group = ++p->re->groups;
                p->re->names = realloc(p->re->names, sizeof(char*) * (size_t)(group + 1));
                if (!p->re->names) rt_panic("regex allocation failed");
                p->re->names[0] = NULL;
                for (int32_t i = 1; i < group; i++) if (p->re->names[i] && (int64_t)strlen(p->re->names[i]) == p->at - start && !memcmp(p->re->names[i], p->pattern + start, (size_t)(p->at - start))) { rx_fail(p, "duplicate group name"); return NULL; }
                p->re->names[group] = rx_alloc((size_t)(p->at - start) + 1);
                memcpy(p->re->names[group], p->pattern + start, (size_t)(p->at - start));
                p->at++;
            } else {
                int32_t flags = p->flags;
                int body = rx_flags(p, &flags);
                if (body < 0) return NULL;
                if (!body) { p->flags = flags; return rx_node(p, RN_EMPTY); }
                p->flags = flags;
            }
        } else {
            group = ++p->re->groups;
            p->re->names = realloc(p->re->names, sizeof(char*) * (size_t)(group + 1));
            if (!p->re->names) rt_panic("regex allocation failed");
            p->re->names[0] = NULL; p->re->names[group] = NULL;
        }
        RxNode* inner = rx_alternation(p);
        p->flags = saved;
        if (!inner) return NULL;
        if (rx_peek(p) != ')') { rx_fail(p, "unclosed group"); return NULL; }
        p->at++;
        if (group < 0) return inner;
        RxNode* node = rx_node(p, RN_GROUP); node->value = group; rx_add_child(node, inner);
        return node;
    }
    if (c == '[') { p->at++; return rx_class_node(p); }
    if (c == '.') { p->at++; return rx_node(p, RN_ANY); }
    if (c == '^') { p->at++; RxNode* node = rx_node(p, RN_ASSERT); node->value = RX_BOL; return node; }
    if (c == '$') { p->at++; RxNode* node = rx_node(p, RN_ASSERT); node->value = RX_EOL; return node; }
    if (c == '*' || c == '+' || c == '?' || c == '{') { rx_fail(p, "repetition with nothing to repeat"); return NULL; }
    int32_t value;
    if (c == '\\') {
        p->at++;
        int32_t index = rx_new_class(p->re);
        int32_t assertion = 0;
        value = rx_escape(p, &p->re->classes[index], 0, &assertion);
        if (value == -1) return NULL;
        if (value == -3) { p->re->class_count--; RxNode* node = rx_node(p, RN_ASSERT); node->value = assertion; return node; }
        if (value == -2) {
            if (p->flags & RX_IGNORE_CASE) rx_class_fold(&p->re->classes[index]);
            RxNode* node = rx_node(p, RN_CLASS); node->value = index; return node;
        }
        p->re->class_count--;
    } else {
        int32_t size = 1; value = rx_decode(p->pattern, p->length, p->at, &size); p->at += size;
    }
    if ((p->flags & RX_IGNORE_CASE) && ((value >= 'a' && value <= 'z') || (value >= 'A' && value <= 'Z'))) {
        int32_t index = rx_new_class(p->re);
        rx_class_add(&p->re->classes[index], value, value);
        rx_class_fold(&p->re->classes[index]);
        RxNode* node = rx_node(p, RN_CLASS); node->value = index; return node;
    }
    RxNode* node = rx_node(p, RN_CHAR); node->value = value;
    return node;
}

static int rx_number(RxParser* p, int32_t* out) {
    int64_t start = p->at; int32_t value = 0;
    while (p->at < p->length && isdigit(p->pattern[p->at])) {
        value = value * 10 + (p->pattern[p->at++] - '0');
        if (value > RX_MAX_REPEAT) return rx_fail(p, "repetition count too large");
    }
    *out = value;
    return p->at > start;
}

static RxNode* rx_repeat(RxParser* p) {
    RxNode* atom = rx_atom(p);
    if (!atom) return NULL;
    while (p->at < p->length) {
        int c = p->pattern[p->at];
        int32_t min, max;
        if (c == '*') { min = 0; max = -1; p->at++; }
        else if (c == '+') { min = 1; max = -1; p->at++; }
        else if (c == '?') { min = 0; max = 1; p->at++; }
        else if (c == '{') {
            int64_t saved = p->at; p->at++;
            if (!rx_number(p, &min)) { if (p->error[0]) return NULL; p->at = saved; break; }
            max = min;
            if (rx_peek(p) == ',') { p->at++; max = -1; if (isdigit(rx_peek(p)) && !rx_number(p, &max)) return NULL; }
            if (rx_peek(p) != '}') { rx_fail(p, "unclosed repetition"); return NULL; }
            p->at++;
            if (max >= 0 && max < min) { rx_fail(p, "repetition maximum below minimum"); return NULL; }
        } else break;
        if (atom->kind == RN_ASSERT || atom->kind == RN_EMPTY) { rx_fail(p, "repetition of an assertion"); return NULL; }
        RxNode* node = rx_node(p, RN_REPEAT);
        node->min = min; node->max = max;
        if (rx_peek(p) == '?') { node->greedy = 0; p->at++; }
        rx_add_child(node, atom);
        atom = node;
    }
    return atom;
}

static RxNode* rx_concat(RxParser* p) {
    RxNode* node = rx_node(p, RN_CONCAT);
    while (p->at < p->length && p->pattern[p->at] != '|' && p->pattern[p->at] != ')') {
        RxNode* item = rx_repeat(p);
        if (!item) return NULL;
        rx_add_child(node, item);
    }
    return node;
}

static RxNode* rx_alternation(RxParser* p) {
    RxNode* first = rx_concat(p);
    if (!first) return NULL;
    if (rx_peek(p) != '|') return first;
    RxNode* node = rx_node(p, RN_ALT);
    rx_add_child(node, first);
    while (rx_peek(p) == '|') {
        p->at++;
        RxNode* next = rx_concat(p);
        if (!next) return NULL;
        rx_add_child(node, next);
    }
    return node;
}

/* ---- Compiler ---- */

static int32_t rx_emit(Regex* re, int32_t op, int32_t x, int32_t y) {
    if (re->length >= RX_MAX_PROGRAM) return -1;
    re->code = rx_grow(re->code, &re->capacity, re->length + 1, sizeof(RxInst));
    re->code[re->length].op = op; re->code[re->length].x = x; re->code[re->length].y = y;
    return re->length++;
}

static int rx_compile(Regex* re, RxNode* node) {
    switch (node->kind) {
        case RN_EMPTY: return 1;
        case RN_CHAR: return rx_emit(re, RX_CHAR, node->value, 0) >= 0;
        case RN_ANY: return rx_emit(re, (node->flags & RX_DOT_ALL) ? RX_ANY_NL : RX_ANY, 0, 0) >= 0;
        case RN_CLASS: return rx_emit(re, RX_CLASS, node->value, 0) >= 0;
        case RN_ASSERT: return rx_emit(re, RX_ASSERT, node->value, node->flags & RX_MULTILINE) >= 0;
        case RN_CONCAT:
            for (int32_t i = 0; i < node->count; i++) if (!rx_compile(re, node->children[i])) return 0;
            return 1;
        case RN_ALT: {
            int32_t jumps[node->count];
            for (int32_t i = 0; i < node->count; i++) {
                int32_t split = -1;
                if (i + 1 < node->count) { split = rx_emit(re, RX_SPLIT, 0, 0); if (split < 0) return 0; re->code[split].x = re->length; }
                if (!rx_compile(re, node->children[i])) return 0;
                jumps[i] = -1;
                if (i + 1 < node->count) { jumps[i] = rx_emit(re, RX_JMP, 0, 0); if (jumps[i] < 0) return 0; re->code[split].y = re->length; }
            }
            for (int32_t i = 0; i + 1 < node->count; i++) re->code[jumps[i]].x = re->length;
            return 1;
        }
        case RN_GROUP:
            if (rx_emit(re, RX_SAVE, 2 * node->value, 0) < 0) return 0;
            if (!rx_compile(re, node->children[0])) return 0;
            return rx_emit(re, RX_SAVE, 2 * node->value + 1, 0) >= 0;
        case RN_REPEAT: {
            RxNode* body = node->children[0];
            for (int32_t i = 0; i < node->min; i++) if (!rx_compile(re, body)) return 0;
            if (node->max < 0) {
                /* split; save iteration start; body; loop: an iteration that
                 * matched nothing ends the repetition (as in Perl), so empty
                 * bodies neither spin nor discard their captures. */
                int32_t slot = re->loops++;
                int32_t split = rx_emit(re, RX_SPLIT, 0, 0); if (split < 0) return 0;
                int32_t start = re->length;
                if (rx_emit(re, RX_SAVE, -1 - slot, 0) < 0) return 0;
                if (!rx_compile(re, body)) return 0;
                int32_t loop = rx_emit(re, RX_LOOP, slot, split); if (loop < 0) return 0;
                if (node->greedy) { re->code[split].x = start; re->code[split].y = re->length; }
                else { re->code[split].x = re->length; re->code[split].y = start; }
                re->code[loop].y = split;
                return 1;
            }
            int32_t optional = node->max - node->min;
            int32_t splits[optional > 0 ? optional : 1];
            for (int32_t i = 0; i < optional; i++) {
                splits[i] = rx_emit(re, RX_SPLIT, 0, 0); if (splits[i] < 0) return 0;
                int32_t start = re->length;
                if (!rx_compile(re, body)) return 0;
                if (node->greedy) re->code[splits[i]].x = start; else re->code[splits[i]].y = start;
            }
            for (int32_t i = 0; i < optional; i++) { if (node->greedy) re->code[splits[i]].y = re->length; else re->code[splits[i]].x = re->length; }
            return 1;
        }
    }
    return 0;
}

void rt_regex_free(void* pointer) {
    Regex* re = pointer;
    if (!re) return;
    free(re->code);
    for (int32_t i = 0; i < re->class_count; i++) free(re->classes[i].ranges);
    free(re->classes);
    if (re->names) for (int32_t i = 1; i <= re->groups; i++) free(re->names[i]);
    free(re->names);
    free(re->captures);
    free(re);
}

/* The compiled pattern, or NULL with the reason in rt_regex_failure. `flags`:
 * 1 ignore case, 2 multiline (^ and $ at line breaks), 4 dot matches newline. */
void* rt_regex_compile(void* pattern_string, int32_t flags) {
    StringVal pattern = rt_string_obj_value(pattern_string);
    Regex* re = rx_alloc(sizeof(Regex));
    RxParser parser; memset(&parser, 0, sizeof(parser));
    parser.pattern = (const unsigned char*)(pattern.data ? pattern.data : "");
    parser.length = pattern.len; parser.re = re; parser.flags = flags;
    RxNode* tree = rx_alternation(&parser);
    if (tree && parser.at < parser.length) { rx_fail(&parser, parser.pattern[parser.at] == ')' ? "unmatched )" : "unexpected character"); tree = NULL; }
    int ok = tree != NULL;
    if (ok) {
        ok = rx_emit(re, RX_SAVE, 0, 0) >= 0 && rx_compile(re, tree) && rx_emit(re, RX_SAVE, 1, 0) >= 0 && rx_emit(re, RX_MATCH, 0, 0) >= 0;
        if (!ok) snprintf(parser.error, sizeof(parser.error), "pattern too large");
    }
    for (int32_t i = 0; i < parser.node_count; i++) { free(parser.nodes[i]->children); free(parser.nodes[i]); }
    free(parser.nodes);
    if (!ok) {
        snprintf(regex_failure, sizeof(regex_failure), "%s", parser.error);
        rt_regex_free(re);
        return NULL;
    }
    if (!re->names) { re->names = rx_alloc(sizeof(char*)); }
    re->captures = rx_alloc(sizeof(int64_t) * (size_t)(2 * (re->groups + 1)));
    return re;
}

int32_t rt_regex_groups(void* pointer) { return ((Regex*)pointer)->groups; }

/* The number of the group called `name`, or -1. */
int32_t rt_regex_group_index(void* pointer, void* name_string) {
    Regex* re = pointer;
    StringVal name = rt_string_obj_value(name_string);
    for (int32_t i = 1; i <= re->groups; i++)
        if (re->names[i] && (int64_t)strlen(re->names[i]) == name.len && !memcmp(re->names[i], name.data, (size_t)name.len)) return i;
    return -1;
}

void* rt_regex_group_name(void* pointer, int32_t index) {
    Regex* re = pointer;
    const char* name = index >= 1 && index <= re->groups && re->names[index] ? re->names[index] : "";
    size_t size = strlen(name);
    char* copy = malloc(size + 1);
    if (!copy) rt_panic("regex allocation failed");
    memcpy(copy, name, size + 1);
    return rl_string_handle_from_value((StringVal){copy, (int64_t)size});
}

/* ---- Pike VM ---- */

typedef struct { int32_t pc; int64_t* slots; } RxThread;
typedef struct { RxThread* threads; int32_t count; int64_t* slot_store; } RxList;

static int rx_is_word(int32_t c) { return (c >= '0' && c <= '9') || (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || c == '_'; }

static int rx_assert(int32_t kind, int32_t multiline, const unsigned char* text, int64_t length, int64_t at) {
    switch (kind) {
        case RX_BOL: return at == 0 || (multiline && text[at - 1] == '\n');
        case RX_EOL: return at == length || (multiline && text[at] == '\n');
        case RX_BOT: return at == 0;
        case RX_EOT: return at == length;
        case RX_WORD: case RX_NOT_WORD: {
            int before = at > 0 && rx_is_word(text[at - 1]);
            int after = at < length && rx_is_word(text[at]);
            return kind == RX_WORD ? before != after : before == after;
        }
    }
    return 0;
}

static int rx_class_matches(RxClass* c, int32_t value) {
    int found = 0;
    for (int32_t i = 0; i < c->count && !found; i++) if (value >= c->ranges[i].lo && value <= c->ranges[i].hi) found = 1;
    return found != c->negated;
}

/* Follows jumps, splits, saves and assertions from `pc` at `at`, adding the
 * threads that consume input (or match) to `list` in priority order. */
static void rx_add(Regex* re, RxList* list, int32_t* marks, int32_t generation, int32_t pc, int64_t* slots,
                   int32_t nslots, const unsigned char* text, int64_t length, int64_t at) {
    if (marks[pc] == generation) return;
    marks[pc] = generation;
    RxInst* inst = &re->code[pc];
    switch (inst->op) {
        case RX_JMP: rx_add(re, list, marks, generation, inst->x, slots, nslots, text, length, at); return;
        case RX_SPLIT:
            rx_add(re, list, marks, generation, inst->x, slots, nslots, text, length, at);
            rx_add(re, list, marks, generation, inst->y, slots, nslots, text, length, at);
            return;
        case RX_ASSERT:
            if (rx_assert(inst->x, inst->y, text, length, at)) rx_add(re, list, marks, generation, pc + 1, slots, nslots, text, length, at);
            return;
        case RX_SAVE: {
            int32_t slot = inst->x >= 0 ? inst->x : 2 * (re->groups + 1) + (-1 - inst->x);
            int64_t saved = slots[slot];
            slots[slot] = at;
            rx_add(re, list, marks, generation, pc + 1, slots, nslots, text, length, at);
            slots[slot] = saved;
            return;
        }
        case RX_LOOP: {
            /* After the body: repeat unless this iteration matched nothing. */
            int32_t slot = 2 * (re->groups + 1) + inst->x;
            if (slots[slot] == at) {
                RxInst* split = &re->code[inst->y];
                /* The split's targets are the body (right after it) and the exit. */
                int32_t exit = split->x == inst->y + 1 ? split->y : split->x;
                rx_add(re, list, marks, generation, exit, slots, nslots, text, length, at);
            } else rx_add(re, list, marks, generation, inst->y, slots, nslots, text, length, at);
            return;
        }
        default: {
            RxThread* thread = &list->threads[list->count];
            thread->pc = pc;
            thread->slots = list->slot_store + (size_t)list->count * (size_t)nslots;
            memcpy(thread->slots, slots, sizeof(int64_t) * (size_t)nslots);
            list->count++;
        }
    }
}

/* Searches from byte `start`; on a match fills the captures and returns 1. */
int32_t rt_regex_search(void* pointer, void* text_string, int64_t start) {
    Regex* re = pointer;
    StringVal value = rt_string_obj_value(text_string);
    const unsigned char* text = (const unsigned char*)(value.data ? value.data : "");
    int64_t length = value.len;
    if (start < 0 || start > length) return 0;
    int32_t captured = 2 * (re->groups + 1);
    int32_t nslots = captured + re->loops;
    int32_t size = re->length;
    RxList lists[2];
    for (int i = 0; i < 2; i++) {
        lists[i].threads = rx_alloc(sizeof(RxThread) * (size_t)size);
        lists[i].slot_store = rx_alloc(sizeof(int64_t) * (size_t)size * (size_t)nslots);
        lists[i].count = 0;
    }
    int32_t* marks = rx_alloc(sizeof(int32_t) * (size_t)size);
    for (int32_t i = 0; i < size; i++) marks[i] = -1;
    int64_t* scratch = rx_alloc(sizeof(int64_t) * (size_t)nslots);
    int64_t* best = rx_alloc(sizeof(int64_t) * (size_t)nslots);
    int matched = 0;
    int32_t generation = 0;
    RxList* current = &lists[0]; RxList* next = &lists[1];
    int64_t at = start;
    while (1) {
        /* A new thread starts at each position until a match is found (leftmost). */
        if (!matched) {
            for (int32_t i = 0; i < nslots; i++) scratch[i] = -1;
            rx_add(re, current, marks, generation, 0, scratch, nslots, text, length, at);
        }
        /* No live thread: done once matched; otherwise try the next start position. */
        if (current->count == 0 && matched) break;
        int32_t width = 0, c = -1;
        if (at < length) c = rx_decode(text, length, at, &width);
        generation++;
        next->count = 0;
        for (int32_t i = 0; i < current->count; i++) {
            RxThread* thread = &current->threads[i];
            RxInst* inst = &re->code[thread->pc];
            int advance = 0;
            switch (inst->op) {
                case RX_MATCH:
                    memcpy(best, thread->slots, sizeof(int64_t) * (size_t)nslots);
                    matched = 1;
                    i = current->count; /* lower-priority threads lose */
                    break;
                case RX_CHAR: advance = c == inst->x; break;
                case RX_ANY: advance = c >= 0 && c != '\n'; break;
                case RX_ANY_NL: advance = c >= 0; break;
                case RX_CLASS: advance = c >= 0 && rx_class_matches(&re->classes[inst->x], c); break;
            }
            if (advance) rx_add(re, next, marks, generation, thread->pc + 1, thread->slots, nslots, text, length, at + width);
        }
        RxList* swap = current; current = next; next = swap;
        if (at >= length) {
            /* Threads waiting at the end can still reach MATCH only through MATCH itself. */
            for (int32_t i = 0; i < current->count && !matched; i++) {
                if (re->code[current->threads[i].pc].op == RX_MATCH) { memcpy(best, current->threads[i].slots, sizeof(int64_t) * (size_t)nslots); matched = 1; }
            }
            break;
        }
        at += width;
        /* `current` was built with this generation, so the start thread added
         * next shares its marks and cannot duplicate a state already listed
         * (each list holds at most one thread per instruction). */
        if (matched && current->count == 0) break;
    }
    if (matched) memcpy(re->captures, best, sizeof(int64_t) * (size_t)captured);
    for (int i = 0; i < 2; i++) { free(lists[i].threads); free(lists[i].slot_store); }
    free(marks); free(scratch); free(best);
    return matched;
}

/* Start and end byte offsets of group `index` in the last match; -1 when it did not participate. */
int64_t rt_regex_capture_start(void* pointer, int32_t index) {
    Regex* re = pointer;
    if (index < 0 || index > re->groups) return -1;
    return re->captures[2 * index];
}
int64_t rt_regex_capture_end(void* pointer, int32_t index) {
    Regex* re = pointer;
    if (index < 0 || index > re->groups) return -1;
    if (re->captures[2 * index] < 0) return -1;
    return re->captures[2 * index + 1];
}
