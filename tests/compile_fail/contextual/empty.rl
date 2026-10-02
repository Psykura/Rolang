// expect-error: Cannot infer the key and value types of an empty Dict literal; add a type annotation
def main() -> i32 { let d = [:]; let v = []; 0 }
