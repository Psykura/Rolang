#include "../runtime/platform.h"
#include "parallel.h"
#include "../runtime/api.h"

/* Worker threads for `parallel def` functions (std.parallel).
 *
 * Each worker runs its own scheduler, cycle collector and allocation pools
 * (thread-local in a ROLANG_THREADED runtime), so Rolang objects never cross
 * threads and reference counts stay non-atomic. A call to a parallel function
 * encodes its arguments into a SendBuffer (plain bytes), queues a job on the
 * least busy worker and waits on a pipe; the worker decodes the arguments
 * into its own objects, runs the function as a task, and encodes the result
 * for the caller to decode. Workers start on first use: ROLANG_WORKERS of
 * them, else one per processor. */

/* ---- Send buffers: bytes owned by no thread ---- */

typedef struct SendBuffer {
    unsigned char* data;
    size_t size, capacity, read_at;
    int depth;
} SendBuffer;

void* rt_send_buffer_new(void) {
    SendBuffer* buffer = calloc(1, sizeof(SendBuffer));
    if (!buffer) rt_panic("send buffer allocation failed");
    return buffer;
}

void rt_send_buffer_free(void* pointer) {
    SendBuffer* buffer = pointer;
    if (!buffer) return;
    free(buffer->data);
    free(buffer);
}

static void send_reserve(SendBuffer* buffer, size_t extra) {
    if (buffer->size + extra <= buffer->capacity) return;
    size_t next = buffer->capacity ? buffer->capacity * 2 : 256;
    while (next < buffer->size + extra) next *= 2;
    unsigned char* grown = realloc(buffer->data, next);
    if (!grown) rt_panic("send buffer allocation failed");
    buffer->data = grown; buffer->capacity = next;
}

void rt_send_put_i64(void* pointer, int64_t value) {
    SendBuffer* buffer = pointer;
    send_reserve(buffer, 8);
    memcpy(buffer->data + buffer->size, &value, 8);
    buffer->size += 8;
}

void rt_send_put_f64(void* pointer, double value) {
    SendBuffer* buffer = pointer;
    send_reserve(buffer, 8);
    memcpy(buffer->data + buffer->size, &value, 8);
    buffer->size += 8;
}

void rt_send_put_string(void* pointer, void* string) {
    SendBuffer* buffer = pointer;
    StringVal value = rt_string_obj_value(string);
    rt_send_put_i64(buffer, value.len);
    send_reserve(buffer, (size_t)value.len);
    if (value.len) memcpy(buffer->data + buffer->size, value.data, (size_t)value.len);
    buffer->size += (size_t)value.len;
}

/* Nesting of encoded values: a value graph with a cycle would otherwise encode forever. */
void rt_send_enter(void* pointer) {
    SendBuffer* buffer = pointer;
    if (++buffer->depth > 10000) rt_panic("cannot send a value nested more than 10000 levels deep (is it cyclic?)");
}
void rt_send_leave(void* pointer) { ((SendBuffer*)pointer)->depth--; }

static void send_need(SendBuffer* buffer, size_t count) {
    if (buffer->read_at + count > buffer->size) rt_panic("malformed send buffer");
}

int64_t rt_send_get_i64(void* pointer) {
    SendBuffer* buffer = pointer;
    send_need(buffer, 8);
    int64_t value; memcpy(&value, buffer->data + buffer->read_at, 8);
    buffer->read_at += 8;
    return value;
}

double rt_send_get_f64(void* pointer) {
    SendBuffer* buffer = pointer;
    send_need(buffer, 8);
    double value; memcpy(&value, buffer->data + buffer->read_at, 8);
    buffer->read_at += 8;
    return value;
}

void* rt_send_get_string(void* pointer) {
    SendBuffer* buffer = pointer;
    int64_t length = rt_send_get_i64(buffer);
    if (length < 0) rt_panic("malformed send buffer");
    send_need(buffer, (size_t)length);
    char* copy = malloc((size_t)length + 1);
    if (!copy) rt_panic("send buffer allocation failed");
    if (length) memcpy(copy, buffer->data + buffer->read_at, (size_t)length);
    copy[length] = 0;
    buffer->read_at += (size_t)length;
    return rl_string_handle_from_value((StringVal){copy, length});
}

#if defined(__unix__) || defined(__APPLE__)
#include <pthread.h>

/* ---- Jobs, inboxes and workers ---- */

typedef void (*ParallelStart)(void* closure, void* job);

/* A thread's inbox: finished jobs it submitted, and a pipe its scheduler
 * polls (a worker also receives new jobs through it). */
typedef struct Inbox {
    int wake[2];
    pthread_mutex_t lock;
    struct ParallelJob* done;
} Inbox;

typedef struct Worker {
    pthread_t thread;
    Inbox* inbox;
    pthread_mutex_t lock;
    struct ParallelJob* head;
    struct ParallelJob* tail;
    int load;   /* jobs queued or running, updated atomically */
} Worker;

typedef struct ParallelJob {
    pthread_mutex_t lock;
    int owners;               /* the caller's task, and the worker (then the caller's inbox) */
    ParallelStart start;
    SendBuffer* arguments;
    SendBuffer* result;
    TaskHandle* task;         /* the caller's waiting task while it lives; only its thread uses it */
    Inbox* inbox;
    Worker* worker;
    struct ParallelJob* next;
} ParallelJob;

static Worker* workers;
static int worker_count;
static pthread_once_t workers_once = PTHREAD_ONCE_INIT;

static RL_TLS Worker* current_worker;
static RL_TLS Inbox* current_inbox;

static void job_release(ParallelJob* job) {
    pthread_mutex_lock(&job->lock);
    int left = --job->owners;
    pthread_mutex_unlock(&job->lock);
    if (left) return;
    pthread_mutex_destroy(&job->lock);
    rt_send_buffer_free(job->arguments);
    rt_send_buffer_free(job->result);
    free(job);
}

static ParallelJob* job_of(TaskHandle* task) { ParallelJob* job; memcpy(&job, task->peer, sizeof(job)); return job; }

static void wake(Inbox* inbox) {
    char byte = 1;
    ssize_t written = write(inbox->wake[1], &byte, 1);
    (void)written;
}

/* This thread's inbox, created on first use; its pipe joins the scheduler's poll. */
static Inbox* inbox_of_thread(void) {
    if (current_inbox) return current_inbox;
    Inbox* inbox = calloc(1, sizeof(Inbox));
    if (!inbox) rt_panic("parallel inbox allocation failed");
    pthread_mutex_init(&inbox->lock, NULL);
    if (pipe(inbox->wake) < 0) rt_panic("cannot create a wake pipe");
    for (int end = 0; end < 2; end++) {
        (void)fcntl(inbox->wake[end], F_SETFD, FD_CLOEXEC);
        (void)fcntl(inbox->wake[end], F_SETFL, fcntl(inbox->wake[end], F_GETFL) | O_NONBLOCK);
    }
    current_inbox = inbox;
    rl_task_set_wake_fd(inbox->wake[0]);
    return inbox;
}

/* Called by the scheduler when the wake pipe is readable: completes the
 * waiting tasks of finished jobs. */
void rl_parallel_wake(void) {
    Inbox* inbox = current_inbox;
    if (!inbox) return;
    char drain[64];
    while (read(inbox->wake[0], drain, sizeof(drain)) > 0) {}
    pthread_mutex_lock(&inbox->lock);
    ParallelJob* job = inbox->done;
    inbox->done = NULL;
    pthread_mutex_unlock(&inbox->lock);
    while (job) {
        ParallelJob* next = job->next;
        job->next = NULL;
        if (job->task) rl_task_native_result(job->task, 0);
        job_release(job);   /* the inbox's ownership */
        job = next;
    }
}

/* Starts the queued jobs as tasks on this worker's scheduler. */
static void worker_start_jobs(Worker* worker) {
    pthread_mutex_lock(&worker->lock);
    ParallelJob* job = worker->head;
    worker->head = worker->tail = NULL;
    pthread_mutex_unlock(&worker->lock);
    while (job) {
        ParallelJob* next = job->next;
        job->next = NULL;
        job->start(NULL, job);
        job = next;
    }
}

void rl_task_step(void);
int rl_task_has_tasks(void);

static void* worker_main(void* argument) {
    Worker* worker = argument;
    current_worker = worker;
    current_inbox = worker->inbox;
    rl_task_set_wake_fd(worker->inbox->wake[0]);
    while (1) {
        rl_parallel_wake();
        worker_start_jobs(worker);
        if (rl_task_has_tasks()) { rl_task_step(); continue; }
        /* Idle: sleep until a job (or a nested job's result) arrives. */
        struct pollfd wait = { worker->inbox->wake[0], POLLIN, 0 };
        while (poll(&wait, 1, -1) < 0 && errno == EINTR) {}
    }
    return NULL;
}

static void workers_start(void) {
    int count = 0;
    const char* setting = getenv("ROLANG_WORKERS");
    if (setting && *setting) count = atoi(setting);
    if (count <= 0) { long processors = sysconf(_SC_NPROCESSORS_ONLN); count = processors > 0 ? (int)processors : 4; }
    if (count > 256) count = 256;
    workers = calloc((size_t)count, sizeof(Worker));
    if (!workers) rt_panic("worker allocation failed");
    for (int i = 0; i < count; i++) {
        Worker* worker = &workers[i];
        pthread_mutex_init(&worker->lock, NULL);
        worker->inbox = calloc(1, sizeof(Inbox));
        if (!worker->inbox) rt_panic("worker allocation failed");
        pthread_mutex_init(&worker->inbox->lock, NULL);
        if (pipe(worker->inbox->wake) < 0) rt_panic("cannot create a worker wake pipe");
        for (int end = 0; end < 2; end++) {
            (void)fcntl(worker->inbox->wake[end], F_SETFD, FD_CLOEXEC);
            (void)fcntl(worker->inbox->wake[end], F_SETFL, fcntl(worker->inbox->wake[end], F_GETFL) | O_NONBLOCK);
        }
        pthread_attr_t attributes;
        pthread_attr_init(&attributes);
        pthread_attr_setstacksize(&attributes, 8 * 1024 * 1024);
        if (pthread_create(&worker->thread, &attributes, worker_main, worker) != 0) rt_panic("cannot start a worker thread");
        pthread_attr_destroy(&attributes);
        pthread_detach(worker->thread);
    }
    worker_count = count;
}

int32_t rt_parallel_workers(void) {
    pthread_once(&workers_once, workers_start);
    return worker_count;
}

/* Queues `start(job)` on the least busy worker with the encoded arguments
 * (taking ownership of them); the returned task completes once the result is
 * ready. `start_slot` is the address of a variable holding a Rolang function
 * value (`start as RawPtr`): a closure whose code ignores its environment, so
 * only the code pointer crosses threads. */
TaskHandle* rt_parallel_submit(void* start_slot, void* arguments) {
    void* start_closure = start_slot ? *(void**)start_slot : NULL;
    if (!start_closure) rt_panic("parallel job without a function");
#if !defined(ROLANG_THREADED)
    rt_send_buffer_free(arguments);
    rt_panic("parallel functions need a runtime built with ROLANG_THREADED");
#endif
    pthread_once(&workers_once, workers_start);
    Inbox* inbox = inbox_of_thread();
    /* Completed through the inbox, so the task has no descriptor of its own to poll. */
    TaskHandle* task = rl_task_new(); task->native_kind = 13;
    ParallelJob* job = calloc(1, sizeof(*job));
    if (!job) rt_panic("parallel job allocation failed");
    pthread_mutex_init(&job->lock, NULL);
    job->owners = 2;
    memcpy(task->peer, &job, sizeof(job));
    job->start = *(ParallelStart*)((char*)start_closure + 32);
    job->arguments = arguments;
    job->task = task;
    job->inbox = inbox;
    Worker* chosen = &workers[0];
    int lowest = __atomic_load_n(&workers[0].load, __ATOMIC_RELAXED);
    for (int i = 1; i < worker_count; i++) {
        int load = __atomic_load_n(&workers[i].load, __ATOMIC_RELAXED);
        if (load < lowest) { lowest = load; chosen = &workers[i]; }
    }
    job->worker = chosen;
    __atomic_add_fetch(&chosen->load, 1, __ATOMIC_RELAXED);
    pthread_mutex_lock(&chosen->lock);
    if (chosen->tail) chosen->tail->next = job; else chosen->head = job;
    chosen->tail = job;
    pthread_mutex_unlock(&chosen->lock);
    wake(chosen->inbox);
    return task;
}

/* On the worker: the job's arguments, as a reader that now owns them. */
void* rt_parallel_arguments(void* pointer) {
    ParallelJob* job = pointer;
    SendBuffer* arguments = job->arguments;
    job->arguments = NULL;
    if (!arguments) rt_panic("parallel job arguments taken twice");
    arguments->read_at = 0;
    return arguments;
}

/* On the worker: stores the encoded result (taking ownership) and hands the
 * job, with the worker's ownership, to the caller's inbox. */
void rt_parallel_complete(void* pointer, void* result) {
    ParallelJob* job = pointer;
    job->result = result;
    __atomic_sub_fetch(&job->worker->load, 1, __ATOMIC_RELAXED);
    Inbox* inbox = job->inbox;
    pthread_mutex_lock(&inbox->lock);
    job->next = inbox->done;
    inbox->done = job;
    pthread_mutex_unlock(&inbox->lock);
    wake(inbox);
}

void rl_parallel_ready(TaskHandle* task) { (void)task; }
/* The caller's task is gone (released or cancelled); the job no longer reports to it. */
void rl_parallel_release(TaskHandle* task) {
    ParallelJob* job = job_of(task);
    job->task = NULL;
    job_release(job);
}

/* On the caller, after completion: the result, as a reader that now owns it. */
void* rt_parallel_result(TaskHandle* task) {
    rt_task_borrow_result(task);
    ParallelJob* job = job_of(task);
    SendBuffer* result = job->result;
    job->result = NULL;
    if (!result) rt_panic("parallel job result taken twice");
    result->read_at = 0;
    return result;
}

/* Whether this thread is a worker (code running for a parallel function). */
int32_t rt_parallel_on_worker(void) { return current_worker != NULL; }

#else

int32_t rt_parallel_workers(void) { return 0; }
TaskHandle* rt_parallel_submit(void* start_closure, void* arguments) {
    (void)start_closure; rt_send_buffer_free(arguments);
    rt_panic("parallel functions need POSIX threads");
    return NULL;
}
void* rt_parallel_arguments(void* job) { (void)job; return NULL; }
void rt_parallel_complete(void* job, void* result) { (void)job; (void)result; }
void rl_parallel_ready(TaskHandle* task) { (void)task; }
void rl_parallel_release(TaskHandle* task) { (void)task; }
void rl_parallel_wake(void) {}
void* rt_parallel_result(TaskHandle* task) { (void)task; return NULL; }
int32_t rt_parallel_on_worker(void) { return 0; }

#endif
