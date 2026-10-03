#ifndef ROLANG_RUNTIME_TASK_H
#define ROLANG_RUNTIME_TASK_H

#include "abi.h"
typedef struct AsyncStream { int fd; int refs; } AsyncStream;
typedef struct TaskHandle {
    void* frame;
    void (*resume_fn)(void*);
    int32_t completed;
    int32_t result_kind;
    void* result;
    int refs, cancelled, running, owns_dependency;
    struct TaskHandle *dependency, *next;
    int native_kind; /* 0 frame, 1 timer, 2 read, 3 write, 4 connect, 5 accept, 6 send to, 7 receive from, 8 resolve, 9 readable, 10 writable */
    int64_t deadline;
    AsyncStream* stream;
    AsyncStream* result_stream;
    char* buffer;
    int32_t length, offset;
    /* Datagram peer address (a struct sockaddr_storage) for send to/receive from. */
    char peer[128];
    int32_t peer_size;
} TaskHandle;
enum { RT_TASK_RESULT_NONE, RT_TASK_RESULT_BOX, RT_TASK_RESULT_HEAP_REF };

#endif /* ROLANG_RUNTIME_TASK_H */
