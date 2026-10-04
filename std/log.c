#include "../runtime/platform.h"
#include "log.h"

/* Process-wide settings for std.log: the minimum level (0 debug, 1 info,
 * 2 warning, 3 error, 4 off) and the output format. The level starts from
 * ROLANG_LOG (debug, info, warning, error or off), else info. */
static int32_t log_level = -1;
static int32_t log_json = 0;

int32_t rt_log_level(void) {
    if (log_level < 0) {
        const char* setting = getenv("ROLANG_LOG");
        log_level = 1;
        if (setting) {
            if (!strcmp(setting, "debug")) log_level = 0;
            else if (!strcmp(setting, "info")) log_level = 1;
            else if (!strcmp(setting, "warning") || !strcmp(setting, "warn")) log_level = 2;
            else if (!strcmp(setting, "error")) log_level = 3;
            else if (!strcmp(setting, "off")) log_level = 4;
        }
    }
    return log_level;
}
void rt_log_set_level(int32_t level) { log_level = level < 0 ? 0 : level > 4 ? 4 : level; }
int32_t rt_log_json(void) { return log_json; }
void rt_log_set_json(int32_t enabled) { log_json = enabled != 0; }
