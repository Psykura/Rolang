
import "path.rl"
import "io.rl"

def main() -> i32 {
    println(path_join("src", "rolang"));
    println(path_join("/abs", "child"));
    println(path_join("", "lone"));
    println(path_join("trailing/", "child"));
    return 0;
}
