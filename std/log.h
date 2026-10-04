#ifndef ROLANG_STD_LOG_H
#define ROLANG_STD_LOG_H

#include "../runtime/abi.h"

int32_t rt_log_level(void);
void rt_log_set_level(int32_t level);
int32_t rt_log_json(void);
void rt_log_set_json(int32_t enabled);

#endif /* ROLANG_STD_LOG_H */
