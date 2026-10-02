enum List<T> { case cons(T, List<T>); case empty; }
def sum(l: List<i32>) -> i32 { switch l { case .cons(let h, let t): h + sum(t); case .empty: 0; } }
def main() -> i32 { let l = List<i32>.cons(40, List<i32>.cons(2, List<i32>.empty)); if sum(l) == 42 { return 0; } 1 }
