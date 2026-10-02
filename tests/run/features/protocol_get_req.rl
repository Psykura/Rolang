protocol HasSize { var size: i32 { get }; }
struct SizedBox { var size: i32 }
def get_size<T: HasSize>(x: T) -> i32 { x.size }
def main() -> i32 { if get_size(SizedBox { size: 42 }) == 42 { return 0; } 1 }
