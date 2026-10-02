// expect-error: Module not found: 'lib.rl'
import "lib.rl" as L
typealias A = L.Hidden;
def main() -> i32 { return 0; }