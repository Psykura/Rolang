
import "io.rl"

def helper() async -> Void {
    println("helper");
    return;
}

def child() async -> Void {
    await helper();
    return;
}

def parent() async -> Void {
    await child();
    await child();
    return;
}

def main() async -> i32 {
    await parent();
    return 0;
}
