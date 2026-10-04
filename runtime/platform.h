#ifndef ROLANG_RUNTIME_PLATFORM_H
#define ROLANG_RUNTIME_PLATFORM_H

/* ROLANG_THREADED (set by the compiler driver) gives each worker thread its
 * own scheduler, cycle collector and allocation pools: objects never cross
 * threads, so reference counts stay non-atomic. Without it (a runtime built
 * by an older compiler) the state is process-wide, as generated code from
 * such a compiler expects. */
#if defined(ROLANG_THREADED)
#define RL_TLS __thread
#else
#define RL_TLS
#endif


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
#include <netdb.h>
#include <sys/socket.h>
#include <fcntl.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <dirent.h>
#include <libgen.h>
#endif

#endif /* ROLANG_RUNTIME_PLATFORM_H */
