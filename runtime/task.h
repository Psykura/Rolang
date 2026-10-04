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
    int native_kind; /* 0 frame, 1 timer, 2 read, 3 write, 4 connect, 5 accept, 6 send to, 7 receive from, 8 resolve, 9 readable, 10 writable, 11 child exit, 12 file operation, 13 parallel job */
    int64_t deadline;
    AsyncStream* stream;
    AsyncStream* result_stream;
    char* buffer;
    int32_t length, offset;
    /* Datagram peer address (a struct sockaddr_storage) for send to/receive from. */
    char peer[128];
    int32_t peer_size;
    /* Runs to completion even when its Task is released (parallel jobs on workers). */
    int detached;
    /* Scheduler bookkeeping (runtime/scheduler.c): every live task is on the
     * all list (`next`/`all_prev`); runnable ones on the ready queue; native
     * ones on the native list once seen; finished ones on the retire queue;
     * tasks awaiting this one on its `waiters` list (linked by `wait_next`).
     * Each queue membership holds a reference. */
    struct TaskHandle *all_prev, *ready_next, *native_next, *native_prev, *retire_next, *waiters, *wait_next;
    int in_ready, in_native, in_retire;
} TaskHandle;
enum { RT_TASK_RESULT_NONE, RT_TASK_RESULT_BOX, RT_TASK_RESULT_HEAP_REF };

#endif /* ROLANG_RUNTIME_TASK_H */
