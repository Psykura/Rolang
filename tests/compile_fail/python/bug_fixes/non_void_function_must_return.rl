// expect-error: TYPE_MISMATCH: function 'f' must return a value of type i32 on all paths

def f() -> i32 {
}
def main() -> i32 { return f(); }
