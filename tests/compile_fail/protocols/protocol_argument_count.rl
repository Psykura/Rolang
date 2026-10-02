// expect-error: Protocol 'Source' expects 1 type argument(s) for Output, got 2
protocol Source<Output> { def next() -> Output?; }
def drain<S: Source<i32, String>>(s: S) -> i32 { 0 }
def main() -> i32 { 0 }
