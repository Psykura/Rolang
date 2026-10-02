
import "io.rl"

struct File {
    var fd: i32;

    def __release__() -> Void {
        println("closing fd:");
        println(f"{self.fd}");
    }
}

def main() -> i32 {
    let _ = File { fd: 42 };
    return 0;
}
