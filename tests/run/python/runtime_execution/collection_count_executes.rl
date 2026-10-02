// expect-exit: 5

def main() -> i32 {
    let xs = [10, 20, 30];
    let values = ["a": 1, "b": 2];
    return xs.len() + (values.len() as i32);
}
