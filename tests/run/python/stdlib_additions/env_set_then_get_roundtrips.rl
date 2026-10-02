
import "process.rl"
import "io.rl"

def main() -> i32 {
    env_set("ROLANG_RT_KEY", "value-42");
    let v = env_get("ROLANG_RT_KEY");
    println(v);
    return 0;
}
