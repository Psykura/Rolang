// Standard library: Result<T, E> for error handling.
//
// Usage:
//     let r: Result<i32, String> = Result.ok(value: 42);
//     if is_ok(r) { ... }

pub enum Result<T, E> {
    case ok(value: T);
    case err(error: E);
}

// Check variant ------------------------------------------------------------

pub def is_ok<T, E>(r: Result<T, E>) -> Bool {
    return switch r {
        case .ok(let v): true;
        default: false;
    };
}

pub def is_err<T, E>(r: Result<T, E>) -> Bool {
    return switch r {
        case .err(let e): true;
        default: false;
    };
}

// Unwrap with a caller-provided default. A panicking `unwrap` is now
// available via `import "panic.rl"; let v = unwrap_or(r, x);` plus an
// explicit panic from the err arm; this helper just returns `default`.
pub def unwrap_or<T, E>(r: Result<T, E>, default: T) -> T {
    return switch r {
        case .ok(let v): v;
        default: default;
    };
}

// Map ---------------------------------------------------------------------

pub def map<T, U, E>(r: Result<T, E>, f: (T) -> U) -> Result<U, E> {
    return switch r {
        case .ok(let v): Result<U, E>.ok(value: f(v));
        case .err(let e): Result<U, E>.err(error: e);
    };
}

// Transform errors while preserving a successful value.
pub def map_err<T, E, F>(r: Result<T, E>, transform: (E) -> F) -> Result<T, F> {
    return switch r {
        case .ok(let value): Result<T, F>.ok(value: value);
        case .err(let error): Result<T, F>.err(error: transform(error));
    };
}

pub def and_then<T, U, E>(r: Result<T, E>, transform: (T) -> Result<U, E>) -> Result<U, E> {
    return switch r {
        case .ok(let value): transform(value);
        case .err(let error): Result<U, E>.err(error: error);
    };
}
