// Values created in async loops are released each iteration, and awaited tasks
// (spawned or started through async function values) are freed.
import std.task
extern "C" def rt_task_live_count() -> i64;
struct Counter { var released: i32; }
struct Probe { var c: Counter; def __release__() -> Void { self.c.released += 1; } }
def work(x: i32) async -> i32 { x + 1 }
def loop_values(c: Counter) async -> Void { for i in 0..<50 { let p = Probe { c }; await yield_now(); } }
def live() -> i64 { var count: i64 = 0; unsafe { count = rt_task_live_count(); } count }
def main() async -> i32 {
    let c = Counter { released: 0 };
    await loop_values(c);
    if c.released != 50 { return 1; }
    let before = live();
    let f = work;
    let g = (x: i32) async -> i32 { x * 2 };
    for i in 0..<50 { let t = spawn work(i); await t; await f(i); await g(i); let u = spawn g(i); await u; }
    // The scheduler retires completed tasks on its next step; the count must not grow per iteration.
    await yield_now();
    if live() > before + 2 { return 2; }
    0
}
