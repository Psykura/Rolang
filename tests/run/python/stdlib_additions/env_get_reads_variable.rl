
import "process.rl"
import "io.rl"

def main() -> i32 {
    let v = env_get("ROLANG_TEST_VAR");
    println(v);
    return 0;
}
