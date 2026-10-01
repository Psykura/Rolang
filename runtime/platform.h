#ifndef ROLANG_RUNTIME_PLATFORM_H
#define ROLANG_RUNTIME_PLATFORM_H


#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <errno.h>
#include <limits.h>
#include <time.h>
#include <sys/stat.h>
#if defined(__unix__) || defined(__APPLE__)
#include <unistd.h>
#include <sched.h>
#include <poll.h>
#include <arpa/inet.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <fcntl.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <dirent.h>
#include <libgen.h>
#endif

#endif /* ROLANG_RUNTIME_PLATFORM_H */
