#include "platform.h"
#include "api.h"

/* ============================================================================
 * Panic / abort path
 *
 * Used by codegen-emitted runtime checks (divide-by-zero, array out-of-bounds,
 * etc.) and by direct rt_* helpers below. Prints a diagnostic on stderr in a
 * "rolang panic: ..." format and aborts the process. Never returns.
 *
 * The "ctx" string is a short description of the failing operation, e.g.
 * "array index out of bounds" or "integer divide by zero". "extra" gives an
 * operation-dependent numeric detail (index value, modulus value, ...).
 *
 * For ergonomics, the wrappers below all have predictable names that codegen
 * can rely on (rt_panic_index_out_of_bounds, rt_panic_divide_by_zero).
 * ============================================================================ */

__attribute__((noreturn))
void rt_panic(const char* ctx) {
    if (ctx == NULL) ctx = "(unknown)";
    fprintf(stderr, "rolang panic: %s\n", ctx);
    fflush(stderr);
    abort();
}

__attribute__((noreturn))
void rt_panic_index_out_of_bounds(int64_t index, int64_t len) {
    fprintf(stderr,
            "rolang panic: index out of bounds: the len is %lld but the index is %lld\n",
            (long long)len, (long long)index);
    fflush(stderr);
    abort();
}

__attribute__((noreturn))
void rt_panic_divide_by_zero(void) {
    fprintf(stderr, "rolang panic: attempt to divide by zero\n");
    fflush(stderr);
    abort();
}

__attribute__((noreturn))
void rt_panic_remainder_by_zero(void) {
    fprintf(stderr, "rolang panic: attempt to calculate the remainder with a divisor of zero\n");
    fflush(stderr);
    abort();
}

/*
 * Emitted by codegen for `expr as! TargetType` when the dynamic witness
 * pointer doesn't match the expected (target, protocol) pair. The cast
 * cannot proceed safely — abort with a clear diagnostic.
 */
__attribute__((noreturn))
void rt_panic_invalid_cast(void) {
    fprintf(stderr,
            "rolang panic: forced downcast (`as!`) failed: existential does "
            "not carry the expected concrete type\n");
    fflush(stderr);
    abort();
}
