
import "path.rl"
import "string.rl"
import "io.rl"

def main() -> i32 {
    println(path_extension("hello.rl"));
    println(path_extension("Makefile"));
    println(path_extension(".gitignore"));
    println(path_extension("dir.with.dots/file"));
    return 0;
}
