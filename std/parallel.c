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
    /* Channel references the encoded bytes hold (by index), released if the
     * buffer is freed before they are decoded. */
    void** channels;
    int32_t channel_count, channel_capacity;
} SendBuffer;

void* rt_send_buffer_new(void) {
    SendBuffer* buffer = calloc(1, sizeof(SendBuffer));
    if (!buffer) rt_panic("send buffer allocation failed");
    return buffer;
}

void rt_send_buffer_free(void* pointer) {
    SendBuffer* buffer = pointer;
    if (!buffer) return;
    for (int32_t i = 0; i < buffer->channel_count; i++) {
        if (buffer->channels[i]) rt_channel_release(buffer->channels[i]);
    }
    free(buffer->channels);
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

/* A channel handle: the buffer owns a reference until it is decoded. */
void rt_send_put_channel(void* pointer, void* channel) {
    SendBuffer* buffer = pointer;
    if (buffer->channel_count == buffer->channel_capacity) {
        int32_t capacity = buffer->channel_capacity ? buffer->channel_capacity * 2 : 4;
        void** grown = realloc(buffer->channels, (size_t)capacity * sizeof(void*));
        if (!grown) rt_panic("send buffer allocation failed");
        buffer->channels = grown; buffer->channel_capacity = capacity;
    }
    rt_channel_retain(channel);
    buffer->channels[buffer->channel_count] = channel;
    rt_send_put_i64(buffer, buffer->channel_count++);
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

/* The channel handle, with the buffer's reference. */
void* rt_send_get_channel(void* pointer) {
    SendBuffer* buffer = pointer;
    int64_t index = rt_send_get_i64(buffer);
    if (index < 0 || index >= buffer->channel_count || !buffer->channels[index]) rt_panic("malformed send buffer");
    void* channel = buffer->channels[index];
    buffer->channels[index] = NULL;
    return channel;
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
    struct ChannelWait* woken;
    int signalled;   /* a byte is in the pipe and not drained yet */
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
    if (__atomic_exchange_n(&inbox->signalled, 1, __ATOMIC_ACQ_REL)) return;
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

static void channel_waits_deliver(struct ChannelWait* wait);

/* Called by the scheduler when the wake pipe is readable: completes the
 * waiting tasks of finished jobs and of woken channel operations. */
void rl_parallel_wake(void) {
    Inbox* inbox = current_inbox;
    if (!inbox) return;
    char drain[64];
    /* Cleared after draining: a wake that sees it clear writes a byte this
     * drain did not take, so the flag is never set with the pipe empty. */
    while (read(inbox->wake[0], drain, sizeof(drain)) > 0) {}
    __atomic_store_n(&inbox->signalled, 0, __ATOMIC_SEQ_CST);
    pthread_mutex_lock(&inbox->lock);
    ParallelJob* job = inbox->done;
    inbox->done = NULL;
    struct ChannelWait* woken = inbox->woken;
    inbox->woken = NULL;
    pthread_mutex_unlock(&inbox->lock);
    channel_waits_deliver(woken);
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
        if (__atomic_load_n(&worker->inbox->signalled, __ATOMIC_ACQUIRE)) rl_parallel_wake();
        worker_start_jobs(worker);
        if (rl_task_has_tasks()) { rl_task_step(); continue; }
        /* Idle: sleep until a job (or a nested job's result) arrives. */
        struct pollfd wait = { worker->inbox->wake[0], POLLIN, 0 };
        while (poll(&wait, 1, -1) < 0 && errno == EINTR) {}
        rl_parallel_wake();
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


/* ---- Channels: queues of encoded values shared by threads ----
 *
 * A channel holds SendBuffers; any thread with a handle may send or receive.
 * A task that finds it full (sending) or empty (receiving) registers a
 * ChannelWait and awaits a native task (kind 14); a change wakes one waiter
 * of the other side through its thread's inbox, and the woken task tries
 * again, so a spurious wake costs only a retry. Closing wakes everyone.
 *
 * Values in a channel may hold other channels (or the channel itself), so
 * channels can form cycles that counting alone never frees. `internal`
 * counts a channel's references held by values queued in channels; when a
 * release leaves only such references, channel_collect checks whether the
 * channels reachable from it are referenced only by each other and frees
 * them if so. Moving a value holding channels into or out of a queue, and
 * the check, take channel_graph first, then channel locks. */

typedef struct ChannelWait {
    int owners;                    /* the waiting task, and the channel's list or an inbox */
    struct ParallelChannel* channel;
    TaskHandle* task;              /* only the waiting thread uses it */
    Inbox* inbox;
    int receiving;
    int woken;                     /* under the channel's lock */
    int delivered;                 /* only the waiting thread uses it */
    struct ChannelWait* next;      /* in the channel's list, then in the inbox */
} ChannelWait;

typedef struct ParallelChannel {
    pthread_mutex_t lock;
    int refs;                      /* handles on every thread, encoded handles and waits */
    int64_t capacity;              /* 0: unbounded */
    SendBuffer** items;
    int64_t head, count, slots;
    int closed;
    ChannelWait *receivers, *receivers_tail, *senders, *senders_tail;
    int internal;                  /* references from queued values; changed under channel_graph */
    unsigned mark;                 /* channel_collect's bookkeeping, under channel_graph */
    int incoming;
} ParallelChannel;

static pthread_mutex_t channel_graph = PTHREAD_MUTEX_INITIALIZER;
static int64_t channels_live;   /* for tests: channels not yet freed */

int64_t rt_channel_live_count(void) { return __atomic_load_n(&channels_live, __ATOMIC_ACQUIRE); }
static unsigned channel_epoch;

/* Under channel_graph: values holding channels entered (+1) or left (-1) a queue. */
static void channel_count_internal(SendBuffer* item, int delta) {
    for (int32_t i = 0; i < item->channel_count; i++) {
        ParallelChannel* target = item->channels[i];
        if (target) __atomic_add_fetch(&target->internal, delta, __ATOMIC_RELEASE);
    }
}

/* Takes every queued value out of a channel (under its lock). */
static SendBuffer** channel_take_items(ParallelChannel* channel, int64_t* count) {
    *count = channel->count;
    if (!channel->count) return NULL;
    SendBuffer** items = malloc((size_t)channel->count * sizeof(*items));
    if (!items) rt_panic("channel allocation failed");
    for (int64_t i = 0; i < channel->count; i++) items[i] = channel->items[(channel->head + i) % channel->slots];
    channel->head = 0; channel->count = 0;
    return items;
}

/* Frees values taken out of queues, after uncounting their references. */
static void channel_free_items(SendBuffer** items, int64_t count) {
    int holding = 0;
    for (int64_t i = 0; i < count && !holding; i++) holding = items[i]->channel_count > 0;
    if (holding) {
        pthread_mutex_lock(&channel_graph);
        for (int64_t i = 0; i < count; i++) channel_count_internal(items[i], -1);
        pthread_mutex_unlock(&channel_graph);
    }
    for (int64_t i = 0; i < count; i++) rt_send_buffer_free(items[i]);
    free(items);
}

static void channel_destroy(ParallelChannel* channel) {
    int64_t count;
    SendBuffer** items = channel_take_items(channel, &count);
    free(channel->items);
    pthread_mutex_destroy(&channel->lock);
    free(channel);
    __atomic_sub_fetch(&channels_live, 1, __ATOMIC_ACQ_REL);
    channel_free_items(items, count);
}

static void channel_collect(ParallelChannel* start);

void* rt_channel_new(int64_t capacity) {
    if (capacity < 0) rt_panic("a channel's capacity cannot be negative");
    ParallelChannel* channel = calloc(1, sizeof(*channel));
    if (!channel) rt_panic("channel allocation failed");
    pthread_mutex_init(&channel->lock, NULL);
    channel->refs = 1;
    channel->capacity = capacity;
    __atomic_add_fetch(&channels_live, 1, __ATOMIC_ACQ_REL);
    return channel;
}

void rt_channel_retain(void* pointer) {
    __atomic_add_fetch(&((ParallelChannel*)pointer)->refs, 1, __ATOMIC_RELAXED);
}

void rt_channel_release(void* pointer) {
    ParallelChannel* channel = pointer;
    if (!channel) return;
    int left = __atomic_sub_fetch(&channel->refs, 1, __ATOMIC_ACQ_REL);
    if (left == 0) channel_destroy(channel);
    else if (left == __atomic_load_n(&channel->internal, __ATOMIC_ACQUIRE)) channel_collect(channel);
}

/* Frees the channels reachable from `start` through queued values when
 * nothing outside them refers to any of them. */
static void channel_collect(ParallelChannel* start) {
    rt_channel_retain(start);   /* keeps it alive while checking */
    pthread_mutex_lock(&channel_graph);
    unsigned epoch = ++channel_epoch;
    ParallelChannel** set = malloc(16 * sizeof(*set));
    if (!set) rt_panic("channel allocation failed");
    size_t count = 0, capacity = 16;
    start->mark = epoch; start->incoming = 0; set[count++] = start;
    for (size_t at = 0; at < count; at++) {
        ParallelChannel* channel = set[at];
        pthread_mutex_lock(&channel->lock);
        for (int64_t i = 0; i < channel->count; i++) {
            SendBuffer* item = channel->items[(channel->head + i) % channel->slots];
            for (int32_t k = 0; k < item->channel_count; k++) {
                ParallelChannel* target = item->channels[k];
                if (!target) continue;
                if (target->mark != epoch) {
                    if (count == capacity) {
                        capacity *= 2;
                        ParallelChannel** grown = realloc(set, capacity * sizeof(*set));
                        if (!grown) rt_panic("channel allocation failed");
                        set = grown;
                    }
                    target->mark = epoch; target->incoming = 0; set[count++] = target;
                }
                target->incoming++;
            }
        }
        pthread_mutex_unlock(&channel->lock);
    }
    /* Garbage when every reference to the set comes from inside it (plus
     * this check's own reference to `start`): nothing else can reach it. */
    int garbage = 1;
    for (size_t i = 0; i < count && garbage; i++) {
        int refs = __atomic_load_n(&set[i]->refs, __ATOMIC_ACQUIRE) - (set[i] == start);
        garbage = refs == set[i]->incoming;
    }
    SendBuffer*** taken = NULL;
    int64_t* taken_counts = NULL;
    if (garbage) {
        taken = calloc(count, sizeof(*taken));
        taken_counts = calloc(count, sizeof(*taken_counts));
        if (!taken || !taken_counts) rt_panic("channel allocation failed");
        for (size_t i = 0; i < count; i++) {
            pthread_mutex_lock(&set[i]->lock);
            set[i]->closed = 1;
            taken[i] = channel_take_items(set[i], &taken_counts[i]);
            pthread_mutex_unlock(&set[i]->lock);
            for (int64_t k = 0; k < taken_counts[i]; k++) channel_count_internal(taken[i][k], -1);
        }
    }
    pthread_mutex_unlock(&channel_graph);
    /* Freeing the values drops the set's references to itself. */
    if (garbage) {
        for (size_t i = 0; i < count; i++) {
            for (int64_t k = 0; k < taken_counts[i]; k++) rt_send_buffer_free(taken[i][k]);
            free(taken[i]);
        }
        free(taken); free(taken_counts);
    }
    free(set);
    if (__atomic_sub_fetch(&start->refs, 1, __ATOMIC_ACQ_REL) == 0) channel_destroy(start);
}

static void wait_release(ChannelWait* wait) {
    if (__atomic_sub_fetch(&wait->owners, 1, __ATOMIC_ACQ_REL)) return;
    rt_channel_release(wait->channel);
    free(wait);
}

/* Under the channel's lock: hands the first waiter of a list (or all of
 * them) to its thread's inbox, with the list's ownership. */
static void channel_signal(ParallelChannel* channel, int receivers, int all) {
    ChannelWait** head = receivers ? &channel->receivers : &channel->senders;
    ChannelWait** tail = receivers ? &channel->receivers_tail : &channel->senders_tail;
    while (*head) {
        ChannelWait* wait = *head;
        *head = wait->next;
        if (!*head) *tail = NULL;
        wait->woken = 1;
        Inbox* inbox = wait->inbox;
        pthread_mutex_lock(&inbox->lock);
        wait->next = inbox->woken;
        inbox->woken = wait;
        pthread_mutex_unlock(&inbox->lock);
        wake(inbox);
        if (!all) break;
    }
}

/* On the waiting thread: completes the tasks of woken waits. */
static void channel_waits_deliver(ChannelWait* wait) {
    while (wait) {
        ChannelWait* next = wait->next;
        wait->next = NULL;
        if (wait->task) { wait->delivered = 1; rl_task_native_result(wait->task, 0); }
        wait_release(wait);   /* the inbox's ownership */
        wait = next;
    }
}

/* Takes the writer's bytes when there is room: 1 sent, 0 full, -1 closed. */
int32_t rt_channel_try_send(void* pointer, void* writer) {
    ParallelChannel* channel = pointer;
    SendBuffer* source = writer;
    int holding = source->channel_count > 0;
    if (holding) pthread_mutex_lock(&channel_graph);
    pthread_mutex_lock(&channel->lock);
    int status = channel->closed ? -1 : (channel->capacity && channel->count >= channel->capacity) ? 0 : 1;
    if (status != 1) {
        pthread_mutex_unlock(&channel->lock);
        if (holding) pthread_mutex_unlock(&channel_graph);
        return status;
    }
    if (channel->count == channel->slots) {
        int64_t slots = channel->slots ? channel->slots * 2 : 16;
        SendBuffer** items = malloc((size_t)slots * sizeof(*items));
        if (!items) rt_panic("channel allocation failed");
        for (int64_t i = 0; i < channel->count; i++) items[i] = channel->items[(channel->head + i) % channel->slots];
        free(channel->items);
        channel->items = items; channel->slots = slots; channel->head = 0;
    }
    SendBuffer* item = calloc(1, sizeof(*item));
    if (!item) rt_panic("channel allocation failed");
    *item = *source;
    item->depth = 0;
    memset(source, 0, sizeof(*source));
    channel->items[(channel->head + channel->count) % channel->slots] = item;
    channel->count++;
    if (holding) channel_count_internal(item, 1);
    channel_signal(channel, 1, 0);
    pthread_mutex_unlock(&channel->lock);
    if (holding) pthread_mutex_unlock(&channel_graph);
    return 1;
}

/* The oldest value, as a reader that owns it, or NULL when empty. */
void* rt_channel_try_receive(void* pointer) {
    ParallelChannel* channel = pointer;
    int holding = 0;
    pthread_mutex_lock(&channel->lock);
    while (channel->count && channel->items[channel->head]->channel_count > 0 && !holding) {
        /* The value holds channels: take the graph lock first, then look again. */
        pthread_mutex_unlock(&channel->lock);
        pthread_mutex_lock(&channel_graph);
        holding = 1;
        pthread_mutex_lock(&channel->lock);
    }
    if (channel->count == 0) {
        pthread_mutex_unlock(&channel->lock);
        if (holding) pthread_mutex_unlock(&channel_graph);
        return NULL;
    }
    SendBuffer* item = channel->items[channel->head];
    channel->head = (channel->head + 1) % channel->slots;
    channel->count--;
    if (item->channel_count > 0) channel_count_internal(item, -1);
    channel_signal(channel, 0, 0);
    pthread_mutex_unlock(&channel->lock);
    if (holding) pthread_mutex_unlock(&channel_graph);
    item->read_at = 0;
    return item;
}

/* Whether the channel is closed and empty: nothing will arrive any more. */
int32_t rt_channel_drained(void* pointer) {
    ParallelChannel* channel = pointer;
    pthread_mutex_lock(&channel->lock);
    int drained = channel->closed && channel->count == 0;
    pthread_mutex_unlock(&channel->lock);
    return drained;
}

int32_t rt_channel_closed(void* pointer) {
    ParallelChannel* channel = pointer;
    pthread_mutex_lock(&channel->lock);
    int closed = channel->closed;
    pthread_mutex_unlock(&channel->lock);
    return closed;
}

int64_t rt_channel_len(void* pointer) {
    ParallelChannel* channel = pointer;
    pthread_mutex_lock(&channel->lock);
    int64_t count = channel->count;
    pthread_mutex_unlock(&channel->lock);
    return count;
}

/* Values sent and not received yet stay receivable; later sends fail. */
void rt_channel_close(void* pointer) {
    ParallelChannel* channel = pointer;
    pthread_mutex_lock(&channel->lock);
    channel->closed = 1;
    channel_signal(channel, 1, 1);
    channel_signal(channel, 0, 1);
    pthread_mutex_unlock(&channel->lock);
}

/* A task completing when a receive (or send) may succeed, or NULL when it
 * may already: then the caller tries again at once. */
TaskHandle* rt_channel_wait(void* pointer, int32_t receiving) {
    ParallelChannel* channel = pointer;
    Inbox* inbox = inbox_of_thread();
    pthread_mutex_lock(&channel->lock);
    int ready = channel->closed || (receiving ? channel->count > 0 : (!channel->capacity || channel->count < channel->capacity));
    if (ready) { pthread_mutex_unlock(&channel->lock); return NULL; }
    ChannelWait* wait = calloc(1, sizeof(*wait));
    if (!wait) rt_panic("channel allocation failed");
    TaskHandle* task = rl_task_new(); task->native_kind = 14;
    memcpy(task->peer, &wait, sizeof(wait));
    wait->owners = 2;
    wait->channel = channel;
    rt_channel_retain(channel);
    wait->task = task;
    wait->inbox = inbox;
    wait->receiving = receiving;
    ChannelWait** head = receiving ? &channel->receivers : &channel->senders;
    ChannelWait** tail = receiving ? &channel->receivers_tail : &channel->senders_tail;
    if (*tail) (*tail)->next = wait; else *head = wait;
    *tail = wait;
    pthread_mutex_unlock(&channel->lock);
    return task;
}

/* The waiting task is gone. A wait still listed leaves the list; one woken
 * but never delivered passes its wake to the next waiter. */
void rl_channel_wait_release(TaskHandle* task) {
    ChannelWait* wait; memcpy(&wait, task->peer, sizeof(wait));
    ParallelChannel* channel = wait->channel;
    int listed = 0;
    pthread_mutex_lock(&channel->lock);
    if (!wait->woken) {
        ChannelWait** head = wait->receiving ? &channel->receivers : &channel->senders;
        ChannelWait** tail = wait->receiving ? &channel->receivers_tail : &channel->senders_tail;
        ChannelWait* previous = NULL;
        for (ChannelWait* at = *head; at; previous = at, at = at->next) {
            if (at != wait) continue;
            if (previous) previous->next = wait->next; else *head = wait->next;
            if (*tail == wait) *tail = previous;
            listed = 1;
            break;
        }
    } else if (!wait->delivered) {
        channel_signal(channel, wait->receiving, 0);
    }
    wait->task = NULL;
    pthread_mutex_unlock(&channel->lock);
    if (listed) wait_release(wait);   /* the list's ownership */
    wait_release(wait);               /* the task's */
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
void* rt_channel_new(int64_t capacity) { (void)capacity; rt_panic("channels need POSIX threads"); return NULL; }
void rt_channel_retain(void* channel) { (void)channel; }
int64_t rt_channel_live_count(void) { return 0; }
void rt_channel_release(void* channel) { (void)channel; }
int32_t rt_channel_try_send(void* channel, void* writer) { (void)channel; (void)writer; return -1; }
void* rt_channel_try_receive(void* channel) { (void)channel; return NULL; }
int32_t rt_channel_drained(void* channel) { (void)channel; return 1; }
int32_t rt_channel_closed(void* channel) { (void)channel; return 1; }
int64_t rt_channel_len(void* channel) { (void)channel; return 0; }
void rt_channel_close(void* channel) { (void)channel; }
TaskHandle* rt_channel_wait(void* channel, int32_t receiving) { (void)channel; (void)receiving; return NULL; }
void rl_channel_wait_release(TaskHandle* task) { (void)task; }

#endif
