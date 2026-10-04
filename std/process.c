#include "../runtime/platform.h"
#include "process.h"
#include "../runtime/api.h"
#include "vec.h"

/* ============================================================================
 * Process / environment / argv / exit / stdin / panic-msg
 *
 * These are the externs `process.rl` and `panic.rl` build on.
 *
 * Argv handling: the runtime supplies the actual `int main(int argc, char**)`,
 * stashes argc/argv into globals, and dispatches to the user-renamed entry
 * point `__rolang_user_main` (see the code generator). User code
 * reads argc/argv via `rt_args_count` and `rt_args_get`.
 * ============================================================================ */

#include <errno.h>
#if defined(__linux__) || defined(__APPLE__)
#  include <sys/types.h>
#  include <sys/wait.h>
#  include <dirent.h>
#  include <libgen.h>
#endif

/* Argv globals — populated by rt_main_wrapper at process start. */
static int      rt_argc_global = 0;
static char**   rt_argv_global = NULL;

int32_t rt_args_count(void) {
    return (int32_t)rt_argc_global;
}

StringVal rt_args_get(int32_t index) {
    StringVal out = {NULL, 0};
    if (index < 0 || index >= rt_argc_global || rt_argv_global == NULL) return out;
    const char* s = rt_argv_global[index];
    if (!s) return out;
    int64_t len = (int64_t)strlen(s);
    char* buf = (char*)malloc((size_t)len + 1);
    if (!buf) return out;
    memcpy(buf, s, (size_t)len);
    buf[len] = '\0';
    out.data = buf;
    out.len = len;
    return out;
}

StringVal rt_env_get(StringVal name) {
    StringVal out = {NULL, 0};
    if (!name.data || name.len <= 0 || memchr(name.data, 0, (size_t)name.len)) return out;
    /* getenv expects a C string; name.data is null-terminated by our string
     * constructors but we copy defensively in case it isn't. */
    char stackbuf[256];
    char* cname = stackbuf;
    if ((size_t)name.len + 1 > sizeof(stackbuf)) {
        cname = (char*)malloc((size_t)name.len + 1);
        if (!cname) return out;
    }
    memcpy(cname, name.data, (size_t)name.len);
    cname[name.len] = '\0';

    const char* val = getenv(cname);
    if (cname != stackbuf) free(cname);
    if (!val) return out;

    int64_t len = (int64_t)strlen(val);
    char* buf = (char*)malloc((size_t)len + 1);
    if (!buf) return out;
    memcpy(buf, val, (size_t)len);
    buf[len] = '\0';
    out.data = buf;
    out.len = len;
    return out;
}

int32_t rt_env_set(StringVal name, StringVal value) {
#if defined(__linux__) || defined(__APPLE__)
    if (!name.data || name.len <= 0) return -1;
    char nbuf[256], vbuf[1024];
    char* cname = nbuf;
    char* cval = vbuf;
    if ((size_t)name.len + 1 > sizeof(nbuf)) {
        cname = (char*)malloc((size_t)name.len + 1);
        if (!cname) return -1;
    }
    memcpy(cname, name.data, (size_t)name.len);
    cname[name.len] = '\0';

    if (!value.data || value.len == 0) {
        if (cname != nbuf) { int r = unsetenv(cname); free(cname); return r; }
        return unsetenv(cname);
    }
    if ((size_t)value.len + 1 > sizeof(vbuf)) {
        cval = (char*)malloc((size_t)value.len + 1);
        if (!cval) { if (cname != nbuf) free(cname); return -1; }
    }
    memcpy(cval, value.data, (size_t)value.len);
    cval[value.len] = '\0';

    int rc = setenv(cname, cval, 1);
    if (cname != nbuf) free(cname);
    if (cval != vbuf) free(cval);
    return rc;
#else
    (void)name; (void)value;
    return -1;
#endif
}

/* Run a shell command. Returns the child exit code or -1 on launch failure. */
int32_t rt_process_system(StringVal cmd) {
    if (!cmd.data || cmd.len <= 0) return -1;
    /* Defensive nul-terminate copy. */
    char stackbuf[1024];
    char* c = stackbuf;
    if ((size_t)cmd.len + 1 > sizeof(stackbuf)) {
        c = (char*)malloc((size_t)cmd.len + 1);
        if (!c) return -1;
    }
    memcpy(c, cmd.data, (size_t)cmd.len);
    c[cmd.len] = '\0';
    int rc = system(c);
    if (c != stackbuf) free(c);
#if defined(__linux__) || defined(__APPLE__)
    if (WIFEXITED(rc)) return WEXITSTATUS(rc);
    return rc;
#else
    return rc;
#endif
}

/* Run an external program by argv vector — no shell, no interpolation,
 * no metacharacter expansion. Safe alternative to `system()` for callers
 * who need to feed untrusted data into a command. The argv RawPtr is a
 * Vec<String>'s handle; we walk it via the gvec ABI.
 *
 * Returns the child's exit code, or -1 on launch failure. */
static int64_t rt_process_start_argv_impl(void* argv_vec, const char* log_path) {
#if defined(__linux__) || defined(__APPLE__)
    if (argv_vec == NULL) return -1;
    GVecHeader* h = (GVecHeader*)argv_vec;
    if (h->len <= 0) return -1;
    /* Element size must match a String pointer (heap representation). */
    if (h->elem_size != (int32_t)sizeof(void*)) return -1;

    /* Build a NULL-terminated char* array from the Vec<String>. We allocate
     * separately from the strings themselves so we don't have to scribble
     * into the runtime's own buffers. */
    int n = h->len;
    char** argv = (char**)calloc((size_t)n + 1, sizeof(char*));
    if (!argv) return -1;
    unsigned char* data = (unsigned char*)(h + 1);
    int ok = 1;
    for (int i = 0; i < n; i++) {
        void* str_obj = *(void**)(data + (size_t)i * (size_t)h->elem_size);
        if (!str_obj) { ok = 0; break; }
        /* The String's {data, len} live inline in the ARC object payload;
         * use the canonical accessor rather than assuming a separate heap
         * StringVal handle (the layout prior to the inline-payload change). */
        StringVal sv = rt_string_obj_value(str_obj);
        if (sv.len < 0 || (sv.len && (!sv.data || memchr(sv.data, 0, (size_t)sv.len)))) {
            ok = 0; break;
        }
        size_t len = (size_t)(sv.len > 0 ? sv.len : 0);
        char* dup = (char*)malloc(len + 1);
        if (!dup) { ok = 0; break; }
        if (len > 0 && sv.data != NULL) memcpy(dup, sv.data, len);
        dup[len] = '\0';
        argv[i] = dup;
    }
    if (!ok) {
        for (int i = 0; i < n; i++) free(argv[i]);
        free(argv);
        return -1;
    }
    argv[n] = NULL;

    pid_t pid = fork();
    if (pid < 0) {
        for (int i = 0; i < n; i++) free(argv[i]);
        free(argv);
        return -1;
    }
    if (pid == 0) {
        if (log_path) {
            int fd = open(log_path, O_WRONLY | O_CREAT | O_TRUNC, 0600);
            if (fd < 0 || dup2(fd, STDOUT_FILENO) < 0 || dup2(fd, STDERR_FILENO) < 0) _exit(126);
            if (fd > STDERR_FILENO) close(fd);
        }
        /* child: execvp searches PATH but does not invoke a shell. */
        execvp(argv[0], argv);
        /* If execvp returns, it failed. */
        _exit(127);
    }
    for (int i = 0; i < n; i++) free(argv[i]);
    free(argv);
    return (int64_t)pid;
#else
    (void)argv_vec; (void)log_path;
    return -1;
#endif
}

/* The exit code of a started process, or -1 (killed by a signal, or not started). */
int32_t rt_process_wait_started(int64_t pid) {
#if defined(__linux__) || defined(__APPLE__)
    if (pid <= 0) return -1;
    int status = 0;
    pid_t waited;
    do { waited = waitpid((pid_t)pid, &status, 0); } while (waited < 0 && errno == EINTR);
    if (waited < 0) return -1;
    if (WIFEXITED(status)) return WEXITSTATUS(status);
    if (WIFSIGNALED(status)) return -1;
    return status;
#else
    (void)pid;
    return -1;
#endif
}

static int32_t rt_process_run_argv_impl(void* argv_vec, const char* log_path) {
    return rt_process_wait_started(rt_process_start_argv_impl(argv_vec, log_path));
}

int32_t rt_process_run_argv(void* argv_vec) {
    return rt_process_run_argv_impl(argv_vec, NULL);
}

int32_t rt_process_run_argv_log(void* argv_vec, void* log_obj) {
    StringVal log = rt_string_obj_value(log_obj);
    if (!log.data || log.len <= 0 || memchr(log.data, 0, (size_t)log.len)) return -1;
    return rt_process_run_argv_impl(argv_vec, log.data);
}

/* Starts a program with both output streams in a log file; the process id, or -1. */
int64_t rt_process_start_argv_log(void* argv_vec, void* log_obj) {
    StringVal log = rt_string_obj_value(log_obj);
    if (!log.data || log.len <= 0 || memchr(log.data, 0, (size_t)log.len)) return -1;
    return rt_process_start_argv_impl(argv_vec, log.data);
}

int32_t rt_process_cpu_count(void) {
#if defined(__linux__) || defined(__APPLE__)
    long count = sysconf(_SC_NPROCESSORS_ONLN);
    return count > 0 ? (int32_t)count : 1;
#else
    return 1;
#endif
}

__attribute__((noreturn))
void rt_exit(int32_t code) {
    /* Use _exit (POSIX) rather than libc exit() so we don't risk
     * re-entering any Rolang-defined `exit` symbol via the dynamic
     * link table.
     */
    fflush(stdout);
    fflush(stderr);
#if defined(__linux__) || defined(__APPLE__)
    _exit((int)code);
#else
    exit((int)code);
#endif
}

/* ---- stdin ---- */

StringVal rt_stdin_read_line(void) {
    StringVal out = {NULL, 0};
    size_t cap = 128, len = 0;
    char* buf = (char*)malloc(cap);
    if (!buf) return out;
    int c;
    while ((c = fgetc(stdin)) != EOF) {
        if (len + 1 >= cap) {
            size_t new_cap = cap * 2;
            char* nb = (char*)realloc(buf, new_cap);
            if (!nb) { free(buf); return out; }
            buf = nb; cap = new_cap;
        }
        buf[len++] = (char)c;
        if (c == '\n') break;
    }
    if (len == 0 && c == EOF) { free(buf); return out; }
    buf[len] = '\0';
    out.data = buf;
    out.len = (int64_t)len;
    return out;
}

StringVal rt_stdin_read_all(void) {
    StringVal out = {NULL, 0};
    size_t cap = 4096, len = 0;
    char* buf = (char*)malloc(cap);
    if (!buf) return out;
    int c;
    while ((c = fgetc(stdin)) != EOF) {
        if (len + 1 >= cap) {
            size_t new_cap = cap * 2;
            char* nb = (char*)realloc(buf, new_cap);
            if (!nb) { free(buf); return out; }
            buf = nb; cap = new_cap;
        }
        buf[len++] = (char)c;
    }
    if (len == 0) { free(buf); return out; }
    buf[len] = '\0';
    out.data = buf;
    out.len = (int64_t)len;
    return out;
}

void* rt_args_get_handle(int32_t index) {
    return rl_string_handle_from_value(rt_args_get(index));
}

void* rt_env_get_handle(void* name) {
    StringVal value = rt_env_get(rt_string_obj_value(name));
    // Missing variables are nil; an explicitly empty variable owns a byte
    // buffer and is Some(""). env_get still converts nil to an empty String.
    return value.data ? rl_string_handle_from_value(value) : NULL;
}

int32_t rt_env_set_string(void* name, void* value) {
    return rt_env_set(rt_string_obj_value(name), rt_string_obj_value(value));
}

int32_t rt_process_system_string(void* cmd) {
    return rt_process_system(rt_string_obj_value(cmd));
}

void* rt_stdin_read_line_handle(void) {
    return rl_string_handle_from_value(rt_stdin_read_line());
}

void* rt_stdin_read_all_handle(void) {
    return rl_string_handle_from_value(rt_stdin_read_all());
}

#if defined(__APPLE__)
#include <mach-o/dyld.h>
#endif
void* rt_process_executable_handle(void) {
    char buffer[PATH_MAX + 1];
#if defined(__APPLE__)
    uint32_t size = sizeof(buffer);
    if (_NSGetExecutablePath(buffer, &size)) return NULL;
#elif defined(__linux__)
    ssize_t size = readlink("/proc/self/exe", buffer, sizeof(buffer) - 1);
    if (size < 0 || size >= (ssize_t)sizeof(buffer) - 1) return NULL;
    buffer[size] = 0;
#else
    return NULL;
#endif
    char* path = realpath(buffer, NULL);
    return path ? rl_string_handle_from_value((StringVal){path, (int64_t)strlen(path)}) : NULL;
}

void* rt_process_host_target_handle(void) {
#if defined(__aarch64__) || defined(__arm64__)
#define RL_HOST_ARCH "aarch64"
#elif defined(__x86_64__)
#define RL_HOST_ARCH "x86_64"
#elif defined(__riscv) && __riscv_xlen == 64
#define RL_HOST_ARCH "riscv64"
#else
#define RL_HOST_ARCH "unsupported"
#endif
#if defined(__APPLE__)
    const char* triple = RL_HOST_ARCH "-apple-darwin";
#elif defined(__linux__) && defined(__GLIBC__)
    const char* triple = RL_HOST_ARCH "-unknown-linux-gnu";
#elif defined(__linux__)
    const char* triple = RL_HOST_ARCH "-unknown-linux-musl";
#else
    const char* triple = RL_HOST_ARCH "-unknown-unknown";
#endif
    char* data = strdup(triple);
    return data ? rl_string_handle_from_value((StringVal){data, (int64_t)strlen(data)}) : NULL;
#undef RL_HOST_ARCH
}

void rt_process_set_args(int argc, char** argv) {
    rt_argc_global = argc;
    rt_argv_global = argv;
}
