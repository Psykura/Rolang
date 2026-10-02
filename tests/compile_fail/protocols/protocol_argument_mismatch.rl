// expect-error: does not conform to Source; Method 'next' return type mismatch: expected i32?, got String?
protocol Source<Output> { def next() -> Output?; }
struct Words: Source<i32> { var w: String; def next() -> String? { self.w } }
def main() -> i32 { 0 }
