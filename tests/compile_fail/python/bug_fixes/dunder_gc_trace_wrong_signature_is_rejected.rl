// expect-error: __gc_trace__ on struct 'Container' has an invalid signature; expected void with 3 pointer parameter(s)

pub struct Container {
    var handle: RawPtr

    // Wrong: __gc_trace__ takes 3 RawPtrs.
    pub static def __gc_trace__(payload: RawPtr) -> Void {}
}

def main() -> i32 { return 0; }
