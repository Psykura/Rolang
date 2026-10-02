// expect-error: __release__ on struct 'Box' has an invalid signature; expected void with 1 pointer parameter(s)

pub struct Box {
    var handle: RawPtr

    // Wrong: __release__ should take no extra arguments.
    pub def __release__(extra: i32) -> Void {}
}

def main() -> i32 { return 0; }
