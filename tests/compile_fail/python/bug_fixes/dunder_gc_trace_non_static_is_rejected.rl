// expect-error: __gc_trace__ on struct 'Container' has an invalid signature; expected void with 3 pointer parameter(s)

pub struct Container {
    var handle: RawPtr

    // Missing `static` — implicit self changes the LLVM signature.
    pub def __gc_trace__(payload: RawPtr, cb: RawPtr, ctx: RawPtr) -> Void {}
}

def main() -> i32 { return 0; }
