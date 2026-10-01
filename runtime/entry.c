#include "platform.h"
#include "api.h"
#include "../std/process.h"

/* ============================================================================
 * C entry point — wraps the user's renamed `__rolang_user_main`.
 *
 * The code generator renames the user `main()` to this
 * internal name so we can own the real entry point and capture argv. If
 * you build the runtime standalone (no user code), the linker will report
 * `__rolang_user_main` as undefined — that is the expected failure mode.
 * ============================================================================ */

extern int32_t __rolang_user_main(void);

int main(int argc, char** argv) {
    rt_process_set_args(argc, argv);
    int32_t rc = __rolang_user_main();
    rt_scheduler_shutdown();
    return (int)rc;
}
