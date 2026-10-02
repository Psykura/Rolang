// expect-error: Cannot compare T and T; add the bound T: Comparable
def biggest<T>(a: T, b: T) -> T { if a < b { return b; } a }
def main() -> i32 { biggest(1, 2) }
