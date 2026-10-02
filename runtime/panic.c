#include "platform.h"
#include "api.h"
#if defined(__APPLE__) || defined(__GLIBC__)
#include <execinfo.h>
#include <dlfcn.h>
#define RL_HAVE_BACKTRACE 1
#endif

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
 *
 * Every panic ends in rt_panic_finish: with ROLANG_BACKTRACE set (and not
 * "0") it prints the native call stack, otherwise a hint how to get one.
 * ============================================================================ */

/* Prints the call stack, innermost first, without the runtime's own panic
 * frames. Return addresses are looked up one byte back: a call to a noreturn
 * function can be the last instruction of its caller. */
static void rl_print_backtrace(void) {
#ifdef RL_HAVE_BACKTRACE
    void* frames[64];
    int count = backtrace(frames, 64);
    int shown = 0;
    fprintf(stderr, "stack backtrace:\n");
    for (int i = 1; i < count; i++) {
        Dl_info info;
        const char* name = NULL;
        if (dladdr((char*)frames[i] - 1, &info) && info.dli_sname) name = info.dli_sname;
        if (name && strncmp(name, "rt_panic", 8) == 0) continue;
        if (name && strcmp(name, "__rolang_user_main") == 0) name = "main";
        else if (name && strcmp(name, "main") == 0) break;
        if (name) fprintf(stderr, "  %2d: %s\n", shown, name);
        else fprintf(stderr, "  %2d: %p\n", shown, frames[i]);
        shown++;
    }
#else
    fprintf(stderr, "note: backtraces are not supported on this platform\n");
#endif
}

__attribute__((noreturn))
void rt_panic_finish(void) {
    const char* wanted = getenv("ROLANG_BACKTRACE");
    if (wanted && wanted[0] && strcmp(wanted, "0") != 0) rl_print_backtrace();
    else fprintf(stderr, "note: run with `ROLANG_BACKTRACE=1` to display a backtrace\n");
    fflush(stderr);
    abort();
}

__attribute__((noreturn))
void rt_panic(const char* ctx) {
    if (ctx == NULL) ctx = "(unknown)";
    fprintf(stderr, "rolang panic: %s\n", ctx);
    rt_panic_finish();
}

__attribute__((noreturn))
void rt_panic_index_out_of_bounds(int64_t index, int64_t len) {
    fprintf(stderr,
            "rolang panic: index out of bounds: the len is %lld but the index is %lld\n",
            (long long)len, (long long)index);
    rt_panic_finish();
}

__attribute__((noreturn))
void rt_panic_divide_by_zero(void) {
    fprintf(stderr, "rolang panic: attempt to divide by zero\n");
    rt_panic_finish();
}

__attribute__((noreturn))
void rt_panic_remainder_by_zero(void) {
    fprintf(stderr, "rolang panic: attempt to calculate the remainder with a divisor of zero\n");
    rt_panic_finish();
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
    rt_panic_finish();
}
