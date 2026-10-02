
import "io.rl"

def leaf() async -> i32 {
    return 7;
}

def main() async -> i32 {
    let a = await leaf();
    let b = await leaf();
    println(f"{a + b}");
    return 0;
}
