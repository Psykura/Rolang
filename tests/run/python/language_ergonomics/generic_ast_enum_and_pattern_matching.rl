
enum Expr<T> {
    case literal(value: T);
    case pair(left: Expr<T>?, right: Expr<T>?);
}
def sum(expr: Expr<i32>?) -> i32 {
    if let node = expr {
        switch node {
            case .literal(let n) where n < 0: return 0;
            case .literal(let n): return n;
            case .pair(let left, let right): return sum(left) + sum(right);
        }
    }
    return 0;
}
def identity<T>(value: T) -> T { return value; }
def main() -> i32 {
    let a = Expr<i32>.literal(value: 40);
    let b = Expr<i32>.literal(value: 2);
    let root = Expr<i32>.pair(left: a, right: b);
    return sum(identity(root)) - 42;
}
