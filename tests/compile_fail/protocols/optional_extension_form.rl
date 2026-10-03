// expect-error: an extension of optionals must have the form `extension<T> T?`
extension<T> Vec<T>? {
    def size() -> i64 { 0 }
}
def main() -> i32 { 0 }
