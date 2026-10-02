#include "../runtime/platform.h"
#include "io.h"
#include "../runtime/api.h"

void rt_io_print_str(void* s_obj) {
    StringVal s = rt_string_obj_value(s_obj);
    if (s.data && s.len > 0) {
        fwrite(s.data, 1, (size_t)s.len, stdout);
    }
}

void rt_io_println_str(void* s) {
    rt_io_print_str(s);
    printf("\n");
}

void rt_io_eprintln_str(void* object) {
    StringVal text = rt_string_obj_value(object);
    if (text.data && text.len > 0) fwrite(text.data, 1, (size_t)text.len, stderr);
    fputc('\n', stderr);
}

void rt_io_eprint_str(void* object) {
    StringVal text = rt_string_obj_value(object);
    if (text.data && text.len > 0) fwrite(text.data, 1, (size_t)text.len, stderr);
}

int32_t rt_io_is_terminal(int32_t fd) {
#if defined(__unix__) || defined(__APPLE__)
    return isatty(fd) ? 1 : 0;
#else
    (void)fd;
    return 0;
#endif
}
