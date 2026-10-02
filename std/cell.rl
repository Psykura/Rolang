// Shared storage for a `var` that a closure captures and that is reassigned.
// The compiler introduces cells so closures and the enclosing scope observe the
// same variable; it is not part of the public library API.
pub struct __CaptureCell<T> {
    pub var value: T;
}
