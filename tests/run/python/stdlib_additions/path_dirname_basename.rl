
import "path.rl"
import "io.rl"

def main() -> i32 {
    println(path_dirname("/a/b/c.rl"));
    println(path_basename("/a/b/c.rl"));
    println(path_dirname("bare.rl"));
    println(path_basename("bare.rl"));
    println(path_dirname("/"));
    return 0;
}
