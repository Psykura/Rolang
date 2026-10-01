#ifndef ROLANG_STD_PATH_H
#define ROLANG_STD_PATH_H

#include "../runtime/abi.h"
#include "string.h"
#include <string.h>

static inline const char* rt_checked_path(void* object) {
    StringVal s = rt_string_obj_value(object);
    return s.data && s.len > 0 && !memchr(s.data, 0, (size_t)s.len) ? s.data : NULL;
}

StringVal rt_path_join(StringVal a, StringVal b);
StringVal rt_path_dirname(StringVal p);
StringVal rt_path_basename(StringVal p);
StringVal rt_path_extension(StringVal p);
int32_t rt_path_exists(StringVal p);
int32_t rt_path_is_dir(StringVal p);
int32_t rt_path_is_file(StringVal p);
StringVal rt_path_resolve(StringVal p);
void* rt_dir_list(StringVal path);
void* rt_path_join_handle(void* a, void* b);
void* rt_path_dirname_handle(void* p);
void* rt_path_basename_handle(void* p);
void* rt_path_extension_handle(void* p);
int32_t rt_path_exists_string(void* p);
int32_t rt_path_is_dir_string(void* p);
int32_t rt_path_is_file_string(void* p);
void* rt_path_resolve_handle(void* p);
void* rt_dir_list_handles(void* path_obj);

#endif /* ROLANG_STD_PATH_H */
