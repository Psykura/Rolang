def main() -> i32 {
    let getters = Vec<() -> i32>.new(); let bumps = Vec<() -> Void>.new();
    for i in 0..<3 {
        var value = i * 10;
        getters.push(() -> { value });
        bumps.push(() -> { value += 1; });
    }
    bumps[2](); bumps[2]();
    if getters[0]() == 0 && getters[1]() == 10 && getters[2]() == 22 { return 0; }
    1
}
