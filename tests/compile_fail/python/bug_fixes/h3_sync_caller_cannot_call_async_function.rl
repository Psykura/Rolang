// expect-error: INVALID_OPERATION: async function 'slow' can only be called from an async function; mark the enclosing function 'async' 

def slow() async -> i32 {
    return 5;
}

def main() -> i32 {
    let n = slow();
    return n;
}
