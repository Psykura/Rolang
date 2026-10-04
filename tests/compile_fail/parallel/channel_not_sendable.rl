// expect-error: 'send' requires T: Sendable, but Config does not conform
import std.parallel
struct Config { let name: String; }
def main() async -> i32 {
    let configs = Channel<Config>.new();
    await configs.send(Config { name: "x" });
    0
}
