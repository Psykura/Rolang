
import "io.rl"
import "process.rl"

def main() -> i32 {
    let args = Vec<String>.new();
    args.push("echo");
    args.push("hello; rm -rf /tmp/SHOULD_NOT_HAPPEN && false");
    return run_argv(args);
}
