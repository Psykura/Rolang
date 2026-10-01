#ifndef ROLANG_STD_FS_H
#define ROLANG_STD_FS_H

#include "../runtime/abi.h"
#include "string.h"


ROLANG_INTERNAL void* rl_string_handle_from_value(StringVal s);
void* rt_file_open(const char* path, const char* mode);
void rt_file_close(void* file);
int32_t rt_file_read(void* file, void* buf, int32_t size);
int32_t rt_file_write(void* file, const void* buf, int32_t size);
int32_t rt_file_seek(void* file, int64_t offset, int32_t whence);
int64_t rt_file_tell(void* file);
int32_t rt_file_flush(void* file);
int32_t rt_file_eof(void* file);
void* rt_file_read_all(void* file);
StringVal rt_file_read_all_s(void* file);
void* rt_file_read_line(void* file);
StringVal rt_file_read_line_s(void* file);
int32_t rt_file_write_str(void* file, const void* str);
int64_t rt_file_get_size(const char* path);
void* rt_file_open_s(StringVal path, StringVal mode);
int32_t rt_file_write_s(void* file, StringVal s);
int64_t rt_file_get_size_s(StringVal path);
void* rt_file_open_string(void* path, void* mode);
void* rt_file_open_handle(void* path, int32_t mode);
int32_t rt_file_write_string(void* file, void* s_obj);
int64_t rt_file_get_size_string(void* path);
void* rt_file_read_all_handle(void* file);
void* rt_file_read_line_handle(void* file);
int32_t rt_path_mkdirs(void* object);
void* rt_temp_dir_handle(void* object);
int32_t rt_path_remove(void* object);
int32_t rt_file_move(void* from, void* to);
int32_t rt_file_mode(void* object);
int64_t rt_file_size_checked(void* object);
void* rt_file_read_checked_handle(void* object, int64_t limit);
int32_t rt_file_write_atomic(void* path, void* text, int32_t mode);
int32_t rt_file_copy_atomic(void* from, void* to, int32_t mode);

#endif /* ROLANG_STD_FS_H */
