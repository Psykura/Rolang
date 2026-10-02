// expect-error: Module not found: 'a.rl'
import "a.rl"
import "b.rl"
def main() -> i32 { return accept(create()); }