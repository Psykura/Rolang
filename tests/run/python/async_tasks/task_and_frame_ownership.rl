
import std.task
extern "C" def rt_scheduler_run() -> Void;
extern "C" def rt_task_live_count() -> i64;
extern "C" def rt_obj_live_count() -> i64;
def work(s: String) async -> String { await sleep(0); return s; }
def cancelled(s: String) async -> Void { await sleep(60000); }
def exercise() -> Void {
    let task = spawn work("owned");
    task.wait_blocking();
    let drop = spawn cancelled("drop");
}
def main() -> i32 {
    unsafe {
        let before = rt_obj_live_count();
        var i = 0;
        while i < 100 {
            exercise();
            rt_scheduler_run();
            i = i + 1;
        }
        if rt_task_live_count() != 0 { return 1; }
        if rt_obj_live_count() != before { return 2; }
    }
    return 0;
}
