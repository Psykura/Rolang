// Structured task handles. Dropping the final handle cancels unfinished work.
pub extern "C" def rt_task_gc_trace(payload: RawPtr, cb: RawPtr, ctx: RawPtr) -> Void;
pub extern "C" def rt_task_join(handle: RawPtr) -> RawPtr;
pub extern "C" def rt_task_destroy(handle: RawPtr) -> Void;
pub extern "C" def rt_task_cancel(handle: RawPtr) -> i32;
pub extern "C" def rt_task_poll(handle: RawPtr) -> i32;
pub extern "C" def rt_task_cancelled(handle: RawPtr) -> i32;
pub extern "C" def rt_task_wait_done(handle: RawPtr) async -> Void;
pub extern "C" def rt_async_sleep_start(milliseconds: i64) -> RawPtr;

pub struct Task<T> {
    var handle: RawPtr;

    pub unsafe static def from_handle(handle: RawPtr) -> Task<T> {
        return Task<T> { handle: handle };
    }
    pub unsafe def raw_handle() -> RawPtr { return self.handle; }
    pub static def __gc_trace__(payload: RawPtr, cb: RawPtr, ctx: RawPtr) -> Void {
        unsafe { rt_task_gc_trace(payload, cb, ctx); }
    }
    pub def wait_blocking() -> Bool {
        unsafe { rt_task_join(self.handle); }
        return !self.cancelled();
    }
    pub def __release__() -> Void {
        unsafe {
            let handle = self.handle;
            self.handle = 0 as RawPtr;
            rt_task_destroy(handle);
        }
    }
    pub def cancel() -> Bool {
        unsafe { return rt_task_cancel(self.handle) != 0; }
    }
    pub def done() -> Bool {
        unsafe { return rt_task_poll(self.handle) != 0; }
    }
    pub def cancelled() -> Bool {
        unsafe { return rt_task_cancelled(self.handle) != 0; }
    }
    // Unlike awaiting a result, wait() accepts a cancelled task.
    pub def wait() async -> Bool {
        unsafe { await rt_task_wait_done(self.handle); }
        return !self.cancelled();
    }
}

pub def sleep(milliseconds: i64) async -> Void {
    unsafe {
        let timer = Task<i32> { handle: rt_async_sleep_start(milliseconds) };
        let status = await timer;
    }
}

pub def yield_now() async -> Void {
    await sleep(0);
}
