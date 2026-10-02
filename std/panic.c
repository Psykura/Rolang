#include "../runtime/platform.h"
#include "panic.h"
#include "../runtime/api.h"

__attribute__((noreturn))
void rt_panic_msg(StringVal msg) {
    fflush(stdout);  /* don't lose output buffered before the panic */
    if (msg.data && msg.len > 0) {
        fprintf(stderr, "rolang panic: %.*s\n", (int)msg.len, msg.data);
    } else {
        fprintf(stderr, "rolang panic: (no message)\n");
    }
    rt_panic_finish();
}

__attribute__((noreturn))
void rt_panic_msg_string(void* msg) {
    rt_panic_msg(rt_string_obj_value(msg));
    /* Unreachable — rt_panic_msg is noreturn but the compiler can't always
     * tell through the indirect call wrapper. Keep ``abort`` as belt and
     * braces. */
    abort();
}
