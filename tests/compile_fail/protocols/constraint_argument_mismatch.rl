// expect-error: does not conform to protocol 'Source<i32>'
protocol Source<Output> { def next() -> Output?; }
struct Words: Source { var w: String; def next() -> String? { self.w } }
def drain<S: Source<i32>>(s: S) -> i32 { 0 }
def main() -> i32 { drain(Words { w: "x" }) }
