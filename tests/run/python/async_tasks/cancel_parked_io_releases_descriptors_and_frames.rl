
import std.async_io
import std.result
import std.task
extern "C" def rt_task_live_count() -> i64;
extern "C" def rt_obj_live_count() -> i64;
extern "C" def rt_scheduler_run() -> Void;
def waiting(stream: AsyncStream) async -> Void {
    let data = await stream.read(10);
}
def exercise() async -> Void {
    if let pair = AsyncPipe.create() {
        let reader = spawn waiting(pair.first);
        await sleep(1);
        reader.cancel();
        await reader.wait();
    }
}
def cycle() -> Void {
    let t = spawn exercise();
    t.wait_blocking();
}
def main() -> i32 {
    unsafe {
        let baseline = rt_obj_live_count();
        var i = 0;
        while i < 50 { cycle(); i = i + 1; }
        rt_scheduler_run();
        if rt_task_live_count() != 0 { return 1; }
        if rt_obj_live_count() != baseline { return 2; }
    }
    return 0;
}
