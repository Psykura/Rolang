// expect-error: Module not found: 'api.rl'
import "api.rl" as API
def main() -> i32 { let x: API.Box = nil; return 0; }