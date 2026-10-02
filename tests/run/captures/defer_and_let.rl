struct Log { var text: String; }
def run(log: Log) -> i32 {
    var steps = 0;
    let step = () -> { steps += 1; };
    defer { log.text = f"steps={steps}"; }
    step(); step();
    steps
}
def main() -> i32 {
    let fixed = 40; let read = () -> { fixed + 2 };
    let log = Log { text: "" };
    if run(log) == 2 && log.text == "steps=2" && read() == 42 { return 0; }
    1
}
