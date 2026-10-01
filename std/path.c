#include "../runtime/platform.h"
#include "path.h"
#include "../runtime/api.h"
#include "vec.h"

/* ============================================================================
 * Path manipulation
 * Pure string operations (POSIX-style separators). They don't touch the FS
 * except for `rt_path_*_exists` which calls stat(2).
 * ============================================================================ */

static char* rt_str_dup_n(const char* data, int64_t len) {
    if (len < 0) len = 0;
    char* buf = (char*)malloc((size_t)len + 1);
    if (!buf) return NULL;
    if (len > 0 && data) memcpy(buf, data, (size_t)len);
    buf[len] = '\0';
    return buf;
}

static StringVal rt_str_take(char* data, int64_t len) {
    StringVal s = {data, len};
    return s;
}

StringVal rt_path_join(StringVal a, StringVal b) {
    if (b.len > 0 && b.data && b.data[0] == '/') {
        /* Absolute right-hand side wins. */
        char* buf = rt_str_dup_n(b.data, b.len);
        return rt_str_take(buf, b.len);
    }
    if (a.len == 0) {
        char* buf = rt_str_dup_n(b.data, b.len);
        return rt_str_take(buf, b.len);
    }
    if (b.len == 0) {
        char* buf = rt_str_dup_n(a.data, a.len);
        return rt_str_take(buf, a.len);
    }
    int64_t need_sep = (a.data[a.len - 1] != '/') ? 1 : 0;
    int64_t total = a.len + need_sep + b.len;
    char* buf = (char*)malloc((size_t)total + 1);
    if (!buf) { StringVal e = {NULL, 0}; return e; }
    memcpy(buf, a.data, (size_t)a.len);
    if (need_sep) buf[a.len] = '/';
    memcpy(buf + a.len + need_sep, b.data, (size_t)b.len);
    buf[total] = '\0';
    return rt_str_take(buf, total);
}

StringVal rt_path_dirname(StringVal p) {
    if (p.len == 0 || !p.data) {
        char* buf = rt_str_dup_n(".", 1);
        return rt_str_take(buf, 1);
    }
    /* Strip trailing slashes (but keep the first one for root). */
    int64_t end = p.len;
    while (end > 1 && p.data[end - 1] == '/') end--;
    int64_t slash = -1;
    for (int64_t i = end - 1; i >= 0; i--) {
        if (p.data[i] == '/') { slash = i; break; }
    }
    if (slash < 0) {
        char* buf = rt_str_dup_n(".", 1);
        return rt_str_take(buf, 1);
    }
    if (slash == 0) {
        char* buf = rt_str_dup_n("/", 1);
        return rt_str_take(buf, 1);
    }
    char* buf = rt_str_dup_n(p.data, slash);
    return rt_str_take(buf, slash);
}

StringVal rt_path_basename(StringVal p) {
    if (p.len == 0 || !p.data) {
        StringVal e = {NULL, 0};
        return e;
    }
    int64_t end = p.len;
    while (end > 1 && p.data[end - 1] == '/') end--;
    int64_t slash = -1;
    for (int64_t i = end - 1; i >= 0; i--) {
        if (p.data[i] == '/') { slash = i; break; }
    }
    int64_t start = (slash < 0) ? 0 : slash + 1;
    int64_t len = end - start;
    char* buf = rt_str_dup_n(p.data + start, len);
    return rt_str_take(buf, len);
}

StringVal rt_path_extension(StringVal p) {
    StringVal out = {NULL, 0};
    if (p.len == 0 || !p.data) return out;
    int64_t dot = -1;
    int64_t slash = -1;
    for (int64_t i = p.len - 1; i >= 0; i--) {
        if (p.data[i] == '/') { slash = i; break; }
        if (p.data[i] == '.' && dot < 0) dot = i;
    }
    if (dot < 0 || dot <= slash + 1) return out;  /* leading dot files have no ext */
    int64_t len = p.len - (dot + 1);
    char* buf = rt_str_dup_n(p.data + dot + 1, len);
    return rt_str_take(buf, len);
}

int32_t rt_path_exists(StringVal p) {
    if (p.len == 0 || !p.data) return 0;
    char stackbuf[1024];
    char* c = stackbuf;
    if ((size_t)p.len + 1 > sizeof(stackbuf)) {
        c = (char*)malloc((size_t)p.len + 1);
        if (!c) return 0;
    }
    memcpy(c, p.data, (size_t)p.len);
    c[p.len] = '\0';
    struct stat st;
    int rc = stat(c, &st);
    if (c != stackbuf) free(c);
    return (rc == 0) ? 1 : 0;
}

int32_t rt_path_is_dir(StringVal p) {
    if (p.len == 0 || !p.data) return 0;
    char stackbuf[1024];
    char* c = stackbuf;
    if ((size_t)p.len + 1 > sizeof(stackbuf)) {
        c = (char*)malloc((size_t)p.len + 1);
        if (!c) return 0;
    }
    memcpy(c, p.data, (size_t)p.len);
    c[p.len] = '\0';
    struct stat st;
    int rc = stat(c, &st);
    int is_dir = (rc == 0 && S_ISDIR(st.st_mode)) ? 1 : 0;
    if (c != stackbuf) free(c);
    return is_dir;
}

int32_t rt_path_is_file(StringVal p) {
    if (p.len == 0 || !p.data) return 0;
    char stackbuf[1024];
    char* c = stackbuf;
    if ((size_t)p.len + 1 > sizeof(stackbuf)) {
        c = (char*)malloc((size_t)p.len + 1);
        if (!c) return 0;
    }
    memcpy(c, p.data, (size_t)p.len);
    c[p.len] = '\0';
    struct stat st;
    int rc = stat(c, &st);
    int is_file = (rc == 0 && S_ISREG(st.st_mode)) ? 1 : 0;
    if (c != stackbuf) free(c);
    return is_file;
}

StringVal rt_path_resolve(StringVal p) {
    StringVal out = {NULL, 0};
    if (p.len == 0 || !p.data) return out;
#if defined(__linux__) || defined(__APPLE__)
    char stackbuf[1024];
    char* c = stackbuf;
    if ((size_t)p.len + 1 > sizeof(stackbuf)) {
        c = (char*)malloc((size_t)p.len + 1);
        if (!c) return out;
    }
    memcpy(c, p.data, (size_t)p.len);
    c[p.len] = '\0';
    char resolved[4096];
    char* rc = realpath(c, resolved);
    if (c != stackbuf) free(c);
    if (!rc) {
        /* Fall back to the input string when the path doesn't exist. */
        char* buf = rt_str_dup_n(p.data, p.len);
        return rt_str_take(buf, p.len);
    }
    int64_t len = (int64_t)strlen(resolved);
    char* buf = rt_str_dup_n(resolved, len);
    return rt_str_take(buf, len);
#else
    char* buf = rt_str_dup_n(p.data, p.len);
    return rt_str_take(buf, p.len);
#endif
}

/* Directory listing: returns a heap array packed as a gvec of StringVal.
 * Each entry is a fresh malloc'd copy. Caller must free both the inner
 * strings and the gvec itself via rt_gvec_free. */
void* rt_dir_list(StringVal path) {
#if defined(__linux__) || defined(__APPLE__)
    if (path.len == 0 || !path.data) return NULL;
    char stackbuf[1024];
    char* c = stackbuf;
    if ((size_t)path.len + 1 > sizeof(stackbuf)) {
        c = (char*)malloc((size_t)path.len + 1);
        if (!c) return NULL;
    }
    memcpy(c, path.data, (size_t)path.len);
    c[path.len] = '\0';
    DIR* d = opendir(c);
    if (c != stackbuf) free(c);
    if (!d) return NULL;

    void* vec = rt_gvec_new(16, (int32_t)sizeof(StringVal), 0);
    if (!vec) { closedir(d); return NULL; }
    struct dirent* ent;
    while ((ent = readdir(d)) != NULL) {
        if (strcmp(ent->d_name, ".") == 0 || strcmp(ent->d_name, "..") == 0) continue;
        int64_t nlen = (int64_t)strlen(ent->d_name);
        char* buf = rt_str_dup_n(ent->d_name, nlen);
        if (!buf) continue;
        StringVal entry = {buf, nlen};
        vec = rt_gvec_push(vec, &entry);
    }
    closedir(d);
    return vec;
#else
    (void)path;
    return NULL;
#endif
}

void* rt_path_join_handle(void* a, void* b) {
    return rl_string_handle_from_value(rt_path_join(rt_string_obj_value(a), rt_string_obj_value(b)));
}

void* rt_path_dirname_handle(void* p) {
    return rl_string_handle_from_value(rt_path_dirname(rt_string_obj_value(p)));
}

void* rt_path_basename_handle(void* p) {
    return rl_string_handle_from_value(rt_path_basename(rt_string_obj_value(p)));
}

void* rt_path_extension_handle(void* p) {
    return rl_string_handle_from_value(rt_path_extension(rt_string_obj_value(p)));
}

int32_t rt_path_exists_string(void* p) { return rt_path_exists(rt_string_obj_value(p)); }
int32_t rt_path_is_dir_string(void* p) { return rt_path_is_dir(rt_string_obj_value(p)); }
int32_t rt_path_is_file_string(void* p) { return rt_path_is_file(rt_string_obj_value(p)); }

void* rt_path_resolve_handle(void* p) {
    return rl_string_handle_from_value(rt_path_resolve(rt_string_obj_value(p)));
}

void* rt_dir_list_handles(void* path_obj) {
    void* old_vec = rt_dir_list(rt_string_obj_value(path_obj));
    if (old_vec == NULL) return NULL;
    GVecHeader* old_h = (GVecHeader*)old_vec;
    void* new_vec = rt_gvec_new(old_h->len > 0 ? old_h->len : 1, (int32_t)sizeof(void*), 0);
    if (new_vec == NULL) {
        rt_gvec_free(old_vec);
        return NULL;
    }
    unsigned char* old_data = (unsigned char*)old_vec + sizeof(GVecHeader);
    for (int32_t i = 0; i < old_h->len; i++) {
        StringVal entry = *(StringVal*)(old_data + (size_t)i * sizeof(StringVal));
        void* handle = rl_string_handle_from_value(entry);
        new_vec = rt_gvec_push(new_vec, &handle);
    }
    free(old_vec);
    return new_vec;
}
