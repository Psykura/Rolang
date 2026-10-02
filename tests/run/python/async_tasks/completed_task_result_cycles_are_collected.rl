
import std.task
extern "C" def rt_gc_collect() -> Void;
extern "C" def rt_obj_live_count() -> i64;
extern "C" def rt_task_live_count() -> i64;
struct Box { var task: Task<Box>?; }
struct Churn { var n: i32; def __release__() -> Void {} }
def make() async -> Box { return Box { task: nil }; }
def exercise() async -> Void {
    let task = spawn make();
    let box = await task;
    box.task = task;
}
def cycle() -> Void {
    let driver = spawn exercise();
    driver.wait_blocking();
}
def main() -> i32 {
    unsafe {
        let baseline = rt_obj_live_count();
        cycle();
        // The collector runs after its allocation threshold, including on
        // explicit requests. Keep these allocations observable via a hook.
        var i = 0;
        while i < 12000 { let churn = Churn { n: i }; i = i + 1; }
        rt_gc_collect();
        if rt_task_live_count() != 0 { return 1; }
        if rt_obj_live_count() != baseline { return 2; }
    }
    return 0;
}
