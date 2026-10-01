extern "C" def rt_gc_collect();

def main() -> i32 {
    unsafe { rt_gc_collect(); }
    0
}
