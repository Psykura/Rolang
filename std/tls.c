#include "../runtime/platform.h"
#include "tls.h"
#include "../runtime/api.h"

/* TLS over OpenSSL (1.1.1 or 3.x), loaded with dlopen the first time a
 * context is created: programs that never use TLS do not need the library,
 * and binaries do not record where it was installed. Sessions drive OpenSSL
 * on nonblocking sockets; each step reports whether it must wait for the
 * socket to become readable or writable, and std/tls.rl awaits that. */

#if defined(__unix__) || defined(__APPLE__)
#include <dlfcn.h>
#include <signal.h>
#include <pthread.h>
#ifdef __linux__
#include <sys/auxv.h>
#endif

/* Values from the OpenSSL headers, stable across 1.1.1 and 3.x. */
enum {
    TLS_ERROR_SSL = 1, TLS_ERROR_WANT_READ = 2, TLS_ERROR_WANT_WRITE = 3,
    TLS_ERROR_SYSCALL = 5, TLS_ERROR_ZERO_RETURN = 6,
    TLS_VERIFY_NONE = 0, TLS_VERIFY_PEER = 1,
    TLS_CTRL_MODE = 33, TLS_CTRL_SET_TLSEXT_HOSTNAME = 55, TLS_CTRL_SET_MIN_PROTO_VERSION = 123,
    TLS_MODE_PARTIAL_WRITE = 0x1, TLS_MODE_MOVING_BUFFER = 0x2,
    TLS_VERSION_1_2 = 0x0303, TLS_FILETYPE_PEM = 1,
    TLS_EXT_ERR_OK = 0, TLS_EXT_ERR_NOACK = 3, TLS_NPN_NEGOTIATED = 1
};
/* SSL_R_UNEXPECTED_EOF_WHILE_READING in ERR_LIB_SSL, as OpenSSL 3 packs it. */
#define TLS_UNEXPECTED_EOF ((20UL << 23) | 294UL)

static struct {
    int state; /* 0 not tried, 1 loaded, -1 unavailable */
    void* library; /* libssl, through which std.crypto also finds libcrypto */
    void* (*TLS_client_method)(void);
    void* (*TLS_server_method)(void);
    void* (*SSL_CTX_new)(void*);
    void (*SSL_CTX_free)(void*);
    long (*SSL_CTX_ctrl)(void*, int, long, void*);
    uint64_t (*SSL_CTX_set_options)(void*, uint64_t);
    void (*SSL_CTX_set_verify)(void*, int, void*);
    int (*SSL_CTX_set_default_verify_paths)(void*);
    int (*SSL_CTX_load_verify_locations)(void*, const char*, const char*);
    int (*SSL_CTX_use_certificate_chain_file)(void*, const char*);
    int (*SSL_CTX_use_PrivateKey_file)(void*, const char*, int);
    int (*SSL_CTX_check_private_key)(const void*);
    int (*SSL_CTX_set_alpn_protos)(void*, const unsigned char*, unsigned int);
    void (*SSL_CTX_set_alpn_select_cb)(void*, int (*)(void*, const unsigned char**, unsigned char*, const unsigned char*, unsigned int, void*), void*);
    int (*SSL_select_next_proto)(unsigned char**, unsigned char*, const unsigned char*, unsigned int, const unsigned char*, unsigned int);
    void* (*SSL_new)(void*);
    void (*SSL_free)(void*);
    int (*SSL_set_fd)(void*, int);
    long (*SSL_ctrl)(void*, int, long, void*);
    int (*SSL_set1_host)(void*, const char*);
    void* (*SSL_get0_param)(void*);
    int (*X509_VERIFY_PARAM_set1_ip_asc)(void*, const char*);
    void (*SSL_set_connect_state)(void*);
    void (*SSL_set_accept_state)(void*);
    int (*SSL_do_handshake)(void*);
    int (*SSL_read)(void*, void*, int);
    int (*SSL_write)(void*, const void*, int);
    int (*SSL_shutdown)(void*);
    int (*SSL_get_error)(const void*, int);
    long (*SSL_get_verify_result)(const void*);
    const char* (*X509_verify_cert_error_string)(long);
    void (*SSL_get0_alpn_selected)(const void*, const unsigned char**, unsigned int*);
    const char* (*SSL_get_version)(const void*);
    unsigned long (*ERR_get_error)(void);
    unsigned long (*ERR_peek_error)(void);
    void (*ERR_error_string_n)(unsigned long, char*, size_t);
    const char* (*ERR_reason_error_string)(unsigned long);
    void (*ERR_clear_error)(void);
} tls;

static RL_TLS char tls_failure[512];

static void tls_fail(const char* message) {
    snprintf(tls_failure, sizeof(tls_failure), "%s", message);
}

/* The oldest queued OpenSSL error, or `fallback`; clears the queue. */
static void tls_describe(char* out, size_t size, const char* fallback) {
    unsigned long code = tls.ERR_get_error();
    const char* reason = code ? tls.ERR_reason_error_string(code) : NULL;
    /* OpenSSL 3 marks an errno value with the top bit (ERR_SYSTEM_FLAG). */
    if (code & 0x80000000UL) snprintf(out, size, "%s", strerror((int)(code & 0x7FFFFFFFUL)));
    else if (reason) snprintf(out, size, "%s", reason);
    else if (code) tls.ERR_error_string_n(code, out, size);
    else snprintf(out, size, "%s", fallback);
    tls.ERR_clear_error();
}

/* ROLANG_LIBSSL, when it is an absolute path and the program does not run
 * with elevated privileges (setuid, setgid or file capabilities), where the
 * environment belongs to a less privileged user. */
static const char* tls_library_override(void) {
    const char* path = getenv("ROLANG_LIBSSL");
    if (!path || path[0] != '/') return NULL;
#if defined(__linux__)
    if (getauxval(AT_SECURE)) return NULL;
#elif defined(__APPLE__) || defined(__FreeBSD__) || defined(__OpenBSD__) || defined(__NetBSD__)
    if (issetugid()) return NULL;
#else
    if (getuid() != geteuid() || getgid() != getegid()) return NULL;
#endif
    return path;
}

static pthread_mutex_t tls_load_lock = PTHREAD_MUTEX_INITIALIZER;
static int tls_load_locked(void);

/* Loads once; threads that arrive meanwhile wait. A failure is remembered
 * process-wide, but its message is copied into each caller's buffer. */
static char tls_load_message[512];
static int tls_load(void) {
    if (__atomic_load_n(&tls.state, __ATOMIC_ACQUIRE)) {
        if (tls.state < 0) snprintf(tls_failure, sizeof(tls_failure), "%s", tls_load_message);
        return tls.state > 0;
    }
    pthread_mutex_lock(&tls_load_lock);
    int loaded = tls.state ? tls.state > 0 : tls_load_locked();
    if (!loaded) snprintf(tls_failure, sizeof(tls_failure), "%s", tls_load_message);
    pthread_mutex_unlock(&tls_load_lock);
    return loaded;
}

static int tls_load_locked(void) {
    /* macOS searches the working directory for bare library names, so only
     * absolute paths are tried there. */
    const char* candidates[] = {
        tls_library_override(),
#ifdef __APPLE__
        "/opt/homebrew/opt/openssl@3/lib/libssl.3.dylib",
        "/usr/local/opt/openssl@3/lib/libssl.3.dylib",
        "/opt/local/lib/libssl.3.dylib",
        "/usr/local/lib/libssl.3.dylib",
#else
        "libssl.so.3", "libssl.so.1.1", "libssl.so",
#endif
    };
    void* library = NULL;
    for (size_t i = 0; i < sizeof(candidates) / sizeof(candidates[0]) && !library; i++)
        if (candidates[i] && candidates[i][0]) library = dlopen(candidates[i], RTLD_NOW | RTLD_LOCAL);
    if (!library) {
        snprintf(tls_load_message, sizeof(tls_load_message), "%s", "TLS needs OpenSSL 3 (libssl), which was not found; install it or set ROLANG_LIBSSL to the library's absolute path"); __atomic_store_n(&tls.state, -1, __ATOMIC_RELEASE);
        return 0;
    }
#define TLS_SYMBOL(name) \
    if (!(*(void**)&tls.name = dlsym(library, #name))) { \
        snprintf(tls_load_message, sizeof(tls_load_message), "%s", "the OpenSSL library lacks " #name "; TLS needs OpenSSL 1.1.1 or later"); __atomic_store_n(&tls.state, -1, __ATOMIC_RELEASE); return 0; }
    TLS_SYMBOL(TLS_client_method) TLS_SYMBOL(TLS_server_method)
    TLS_SYMBOL(SSL_CTX_new) TLS_SYMBOL(SSL_CTX_free) TLS_SYMBOL(SSL_CTX_ctrl)
    TLS_SYMBOL(SSL_CTX_set_options) TLS_SYMBOL(SSL_CTX_set_verify)
    TLS_SYMBOL(SSL_CTX_set_default_verify_paths) TLS_SYMBOL(SSL_CTX_load_verify_locations)
    TLS_SYMBOL(SSL_CTX_use_certificate_chain_file) TLS_SYMBOL(SSL_CTX_use_PrivateKey_file)
    TLS_SYMBOL(SSL_CTX_check_private_key) TLS_SYMBOL(SSL_CTX_set_alpn_protos)
    TLS_SYMBOL(SSL_CTX_set_alpn_select_cb) TLS_SYMBOL(SSL_select_next_proto)
    TLS_SYMBOL(SSL_new) TLS_SYMBOL(SSL_free) TLS_SYMBOL(SSL_set_fd) TLS_SYMBOL(SSL_ctrl)
    TLS_SYMBOL(SSL_set1_host) TLS_SYMBOL(SSL_get0_param) TLS_SYMBOL(X509_VERIFY_PARAM_set1_ip_asc)
    TLS_SYMBOL(SSL_set_connect_state) TLS_SYMBOL(SSL_set_accept_state) TLS_SYMBOL(SSL_do_handshake)
    TLS_SYMBOL(SSL_read) TLS_SYMBOL(SSL_write) TLS_SYMBOL(SSL_shutdown) TLS_SYMBOL(SSL_get_error)
    TLS_SYMBOL(SSL_get_verify_result) TLS_SYMBOL(X509_verify_cert_error_string)
    TLS_SYMBOL(SSL_get0_alpn_selected) TLS_SYMBOL(SSL_get_version)
    TLS_SYMBOL(ERR_get_error) TLS_SYMBOL(ERR_peek_error) TLS_SYMBOL(ERR_error_string_n) TLS_SYMBOL(ERR_reason_error_string) TLS_SYMBOL(ERR_clear_error)
#undef TLS_SYMBOL
    tls.library = library;
#ifndef __APPLE__
    /* OpenSSL writes with write(2), which raises SIGPIPE on a closed
     * connection; macOS sockets already set SO_NOSIGPIPE. */
    signal(SIGPIPE, SIG_IGN);
#endif
    __atomic_store_n(&tls.state, 1, __ATOMIC_RELEASE);
    return 1;
}

typedef struct TlsContext {
    void* ctx;
    int refs;
    unsigned char* alpn; /* wire format: length-prefixed protocol names */
    unsigned int alpn_size;
    int verify; /* clients: certificates are verified, so a host name is required */
} TlsContext;

typedef struct TlsSession {
    void* ssl;
    AsyncStream* stream;
    TlsContext* context;
    char error[512];
} TlsSession;

static char* tls_cstring(void* string) {
    StringVal value = rt_string_obj_value(string);
    if (value.len < 0 || memchr(value.data, 0, (size_t)value.len)) return NULL;
    char* text = malloc((size_t)value.len + 1);
    if (!text) rt_panic("TLS allocation failed");
    if (value.len) memcpy(text, value.data, (size_t)value.len);
    text[value.len] = 0;
    return text;
}

static void tls_context_release(TlsContext* context) {
    if (context && --context->refs == 0) {
        tls.SSL_CTX_free(context->ctx);
        free(context->alpn);
        free(context);
    }
}

/* The server picks the first of its protocols the client also offers. */
static int tls_select_alpn(void* ssl, const unsigned char** out, unsigned char* out_size,
                           const unsigned char* offered, unsigned int offered_size, void* argument) {
    (void)ssl;
    TlsContext* context = argument;
    unsigned char* chosen = NULL; unsigned char chosen_size = 0;
    if (tls.SSL_select_next_proto(&chosen, &chosen_size, context->alpn, context->alpn_size,
                                  offered, offered_size) != TLS_NPN_NEGOTIATED) return TLS_EXT_ERR_NOACK;
    *out = chosen; *out_size = chosen_size;
    return TLS_EXT_ERR_OK;
}

/* Comma-separated protocol names to the ALPN wire format. */
static int tls_alpn(TlsContext* context, const char* names) {
    size_t length = strlen(names);
    if (!length) return 1;
    context->alpn = malloc(length + 1);
    if (!context->alpn) rt_panic("TLS allocation failed");
    unsigned int size = 0;
    const char* start = names;
    while (1) {
        const char* end = strchr(start, ',');
        size_t part = end ? (size_t)(end - start) : strlen(start);
        if (part == 0 || part > 255) { tls_fail("ALPN protocol names must be 1 to 255 bytes"); return 0; }
        context->alpn[size++] = (unsigned char)part;
        memcpy(context->alpn + size, start, part); size += (unsigned int)part;
        if (!end) break;
        start = end + 1;
    }
    context->alpn_size = size;
    return 1;
}

/* Clients with default settings share one context: loading the system's
 * trusted certificates takes milliseconds. */
static RL_TLS TlsContext* tls_default_client;

void* rt_tls_context_new(int32_t server, int32_t verify, void* ca_file, void* certificate, void* key, void* alpn) {
    if (!tls_load()) return NULL;
    char* ca = tls_cstring(ca_file); char* cert = tls_cstring(certificate);
    char* private_key = tls_cstring(key); char* protocols = tls_cstring(alpn);
    int shared = !server && verify && ca && !ca[0] && protocols && !protocols[0];
    TlsContext* context = NULL;
    if (shared && tls_default_client) { context = tls_default_client; context->refs++; goto done; }
    char reason[400];
    if (!ca || !cert || !private_key || !protocols) { tls_fail("TLS file names and protocols must not contain NUL"); goto done; }
    context = calloc(1, sizeof(*context));
    if (!context) rt_panic("TLS allocation failed");
    context->refs = 1;
    context->verify = !server && verify;
    context->ctx = tls.SSL_CTX_new(server ? tls.TLS_server_method() : tls.TLS_client_method());
    if (!context->ctx) { tls_describe(reason, sizeof(reason), "cannot create a TLS context"); tls_fail(reason); free(context); context = NULL; goto done; }
    tls.SSL_CTX_ctrl(context->ctx, TLS_CTRL_SET_MIN_PROTO_VERSION, TLS_VERSION_1_2, NULL);
    tls.SSL_CTX_ctrl(context->ctx, TLS_CTRL_MODE, TLS_MODE_PARTIAL_WRITE | TLS_MODE_MOVING_BUFFER, NULL);
    if (!tls_alpn(context, protocols)) goto fail;
    if (server) {
        if (tls.SSL_CTX_use_certificate_chain_file(context->ctx, cert) != 1) {
            char detail[256]; tls_describe(detail, sizeof(detail), "unreadable");
            snprintf(reason, sizeof(reason), "cannot load certificate %s: %s", cert, detail); tls_fail(reason); goto fail;
        }
        if (tls.SSL_CTX_use_PrivateKey_file(context->ctx, private_key, TLS_FILETYPE_PEM) != 1) {
            char detail[256]; tls_describe(detail, sizeof(detail), "unreadable");
            snprintf(reason, sizeof(reason), "cannot load private key %s: %s", private_key, detail); tls_fail(reason); goto fail;
        }
        if (tls.SSL_CTX_check_private_key(context->ctx) != 1) { tls_fail("the private key does not match the certificate"); tls.ERR_clear_error(); goto fail; }
        if (context->alpn_size) tls.SSL_CTX_set_alpn_select_cb(context->ctx, tls_select_alpn, context);
    } else {
        tls.SSL_CTX_set_verify(context->ctx, verify ? TLS_VERIFY_PEER : TLS_VERIFY_NONE, NULL);
        if (verify) {
            int loaded = ca[0] ? tls.SSL_CTX_load_verify_locations(context->ctx, ca, NULL)
                               : tls.SSL_CTX_set_default_verify_paths(context->ctx);
            if (loaded != 1) {
                char detail[256]; tls_describe(detail, sizeof(detail), "unreadable");
                snprintf(reason, sizeof(reason), "cannot load trusted certificates%s%s: %s", ca[0] ? " from " : "", ca, detail);
                tls_fail(reason); goto fail;
            }
        }
        /* SSL_CTX_set_alpn_protos returns 0 on success. */
        if (context->alpn_size && tls.SSL_CTX_set_alpn_protos(context->ctx, context->alpn, context->alpn_size) != 0) {
            tls_fail("cannot set ALPN protocols"); goto fail;
        }
    }
    if (shared) { tls_default_client = context; context->refs++; }
    goto done;
fail:
    tls_context_release(context); context = NULL;
done:
    free(ca); free(cert); free(private_key); free(protocols);
    return context;
}

void rt_tls_context_free(void* context) { tls_context_release(context); }

void* rt_tls_failure(void) {
    size_t size = strlen(tls_failure);
    char* copy = malloc(size + 1);
    if (!copy) rt_panic("TLS allocation failed");
    memcpy(copy, tls_failure, size + 1);
    return rl_string_handle_from_value((StringVal){copy, (int64_t)size});
}

/* A session over `stream`; a client verifies the certificate against `host`. */
void* rt_tls_session_new(void* context_ptr, void* stream_ptr, void* host_string, int32_t server) {
    TlsContext* context = context_ptr; AsyncStream* stream = stream_ptr;
    if (!context || !stream) { tls_fail("TLS needs a context and a stream"); return NULL; }
    char* host = tls_cstring(host_string);
    if (!host) { tls_fail("host names must not contain NUL"); return NULL; }
    void* ssl = tls.SSL_new(context->ctx);
    if (!ssl || tls.SSL_set_fd(ssl, stream->fd) != 1) {
        char reason[256]; tls_describe(reason, sizeof(reason), "cannot create a TLS session"); tls_fail(reason);
        if (ssl) tls.SSL_free(ssl);
        free(host); return NULL;
    }
    if (server) tls.SSL_set_accept_state(ssl);
    else {
        tls.SSL_set_connect_state(ssl);
        if (!host[0] && context->verify) {
            /* A valid chain alone would accept a certificate issued for any host. */
            tls_fail("verifying the server's certificate needs its host name");
            tls.SSL_free(ssl); free(host); return NULL;
        }
        if (host[0]) {
            unsigned char address[16];
            int numeric = inet_pton(AF_INET, host, address) == 1 || inet_pton(AF_INET6, host, address) == 1;
            /* Certificates name IP addresses separately, and SNI carries only DNS names. */
            int named = numeric ? tls.X509_VERIFY_PARAM_set1_ip_asc(tls.SSL_get0_param(ssl), host)
                                : tls.SSL_set1_host(ssl, host);
            if (!numeric) tls.SSL_ctrl(ssl, TLS_CTRL_SET_TLSEXT_HOSTNAME, 0, host);
            if (named != 1) { tls_fail("cannot set the TLS host name"); tls.ERR_clear_error(); tls.SSL_free(ssl); free(host); return NULL; }
        }
    }
    free(host);
    TlsSession* session = calloc(1, sizeof(*session));
    if (!session) rt_panic("TLS allocation failed");
    session->ssl = ssl;
    session->stream = stream; stream->refs++;
    session->context = context; context->refs++;
    return session;
}

void rt_tls_session_free(void* ptr) {
    TlsSession* session = ptr;
    if (!session) return;
    tls.SSL_free(session->ssl);
    rl_stream_release(session->stream);
    tls_context_release(session->context);
    free(session);
}

/* 1 or 2 to wait for a readable or writable socket, 3 for a connection the
 * peer closed with close_notify, 4 for one closed without it (the data may
 * have been truncated by an attacker), or -1 with the session's error set. */
static int tls_step(TlsSession* session, int result) {
    int error = tls.SSL_get_error(session->ssl, result);
    if (error == TLS_ERROR_WANT_READ) return 1;
    if (error == TLS_ERROR_WANT_WRITE) return 2;
    if (error == TLS_ERROR_ZERO_RETURN) { tls.ERR_clear_error(); return 3; }
    if (error == TLS_ERROR_SSL && (tls.ERR_peek_error() & 0x7FFFFFFFUL) == TLS_UNEXPECTED_EOF) { tls.ERR_clear_error(); return 4; }
    if (error == TLS_ERROR_SYSCALL) {
        int code = errno;
        /* OpenSSL 1.1.1 reports an unexpected EOF this way. */
        if (tls.ERR_peek_error() == 0 && (result == 0 || code == 0)) { tls.ERR_clear_error(); return 4; }
        snprintf(session->error, sizeof(session->error), "%s", code ? strerror(code) : "connection failed");
        tls.ERR_clear_error();
        return -1;
    }
    long verified = tls.SSL_get_verify_result(session->ssl);
    if (error == TLS_ERROR_SSL && verified != 0) {
        snprintf(session->error, sizeof(session->error), "certificate verification failed: %s",
                 tls.X509_verify_cert_error_string(verified));
        tls.ERR_clear_error();
        return -1;
    }
    tls_describe(session->error, sizeof(session->error), "TLS failure");
    return -1;
}

/* 0 once established, 1 or 2 to wait, -1 on failure (a closed connection included). */
int32_t rt_tls_handshake(void* ptr) {
    TlsSession* session = ptr;
    tls.ERR_clear_error();
    int result = tls.SSL_do_handshake(session->ssl);
    if (result == 1) return 0;
    int step = tls_step(session, result);
    if (step == 3 || step == 4) { snprintf(session->error, sizeof(session->error), "connection closed during the TLS handshake"); return -1; }
    return step;
}

/* Up to `limit` bytes; status 0 with an empty result is the end of the
 * stream, and status 4 an end without close_notify. */
void* rt_tls_read(void* ptr, int32_t limit, int32_t* status) {
    TlsSession* session = ptr;
    if (limit < 1) limit = 1;
    char* buffer = malloc((size_t)limit + 1);
    if (!buffer) rt_panic("TLS allocation failed");
    tls.ERR_clear_error();
    int result = tls.SSL_read(session->ssl, buffer, limit);
    int32_t count = 0;
    if (result > 0) { count = result; *status = 0; }
    else {
        int step = tls_step(session, result);
        *status = step == 3 ? 0 : step;
    }
    buffer[count] = 0;
    return rl_string_handle_from_value((StringVal){buffer, count});
}

/* Bytes of `data` from `offset` written now; `status` as for reads. */
int32_t rt_tls_write(void* ptr, void* data, int32_t offset, int32_t* status) {
    TlsSession* session = ptr;
    StringVal value = rt_string_obj_value(data);
    *status = 0;
    if (offset >= value.len) return 0;
    int64_t remaining = value.len - offset;
    int chunk = remaining > INT_MAX ? INT_MAX : (int)remaining;
    tls.ERR_clear_error();
    int result = tls.SSL_write(session->ssl, value.data + offset, chunk);
    if (result > 0) return result;
    int step = tls_step(session, result);
    if (step == 3 || step == 4) { snprintf(session->error, sizeof(session->error), "connection closed"); step = -1; }
    *status = step;
    return 0;
}

/* Sends close_notify: 0 when sent (or the connection is gone), 1 or 2 to wait. */
int32_t rt_tls_shutdown(void* ptr) {
    TlsSession* session = ptr;
    tls.ERR_clear_error();
    int result = tls.SSL_shutdown(session->ssl);
    if (result >= 0) return 0;
    int step = tls_step(session, result);
    return step == 1 || step == 2 ? step : 0;
}

void* rt_tls_session_error(void* ptr) {
    TlsSession* session = ptr;
    size_t size = strlen(session->error);
    char* copy = malloc(size + 1);
    if (!copy) rt_panic("TLS allocation failed");
    memcpy(copy, session->error, size + 1);
    return rl_string_handle_from_value((StringVal){copy, (int64_t)size});
}

static void* tls_text(const char* text, size_t size) {
    char* copy = malloc(size + 1);
    if (!copy) rt_panic("TLS allocation failed");
    if (size) memcpy(copy, text, size);
    copy[size] = 0;
    return rl_string_handle_from_value((StringVal){copy, (int64_t)size});
}

void* rt_tls_alpn(void* ptr) {
    TlsSession* session = ptr;
    const unsigned char* data = NULL; unsigned int size = 0;
    tls.SSL_get0_alpn_selected(session->ssl, &data, &size);
    return tls_text((const char*)data, data ? size : 0);
}

void* rt_tls_version(void* ptr) {
    TlsSession* session = ptr;
    const char* version = tls.SSL_get_version(session->ssl);
    return tls_text(version, strlen(version));
}

/* Completes when the session's socket is readable (writable when `writable`). */
TaskHandle* rt_tls_wait_start(void* ptr, int32_t writable) {
    TlsSession* session = ptr;
    TaskHandle* task = rl_task_new();
    task->native_kind = writable ? 10 : 9;
    task->stream = session->stream; session->stream->refs++;
    return task;
}

#else

void* rt_tls_context_new(int32_t server, int32_t verify, void* ca_file, void* certificate, void* key, void* alpn) {
    (void)server; (void)verify; (void)ca_file; (void)certificate; (void)key; (void)alpn; return NULL;
}
void rt_tls_context_free(void* context) { (void)context; }
void* rt_tls_failure(void) {
    static const char message[] = "TLS is not supported on this platform";
    char* copy = malloc(sizeof(message));
    if (!copy) rt_panic("TLS allocation failed");
    memcpy(copy, message, sizeof(message));
    return rl_string_handle_from_value((StringVal){copy, (int64_t)sizeof(message) - 1});
}
void* rt_tls_session_new(void* context, void* stream, void* host, int32_t server) { (void)context; (void)stream; (void)host; (void)server; return NULL; }
void rt_tls_session_free(void* session) { (void)session; }
int32_t rt_tls_handshake(void* session) { (void)session; return -1; }
void* rt_tls_read(void* session, int32_t limit, int32_t* status) { (void)session; (void)limit; *status = -1; return rt_tls_failure(); }
int32_t rt_tls_write(void* session, void* data, int32_t offset, int32_t* status) { (void)session; (void)data; (void)offset; *status = -1; return 0; }
int32_t rt_tls_shutdown(void* session) { (void)session; return 0; }
void* rt_tls_session_error(void* session) { (void)session; return rt_tls_failure(); }
void* rt_tls_alpn(void* session) { (void)session; return rt_tls_failure(); }
void* rt_tls_version(void* session) { (void)session; return rt_tls_failure(); }
TaskHandle* rt_tls_wait_start(void* session, int32_t writable) {
    (void)session; (void)writable;
    TaskHandle* task = rl_task_new(); task->native_kind = 9;
    rl_task_native_result(task, -ENOSYS);
    return task;
}

#endif
