// expect-error: Cannot assign A to B in return value
def k<A, B>(a: A, b: B) -> B { a }
def main() -> i32 { k(1, 2) }
