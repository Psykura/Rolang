import std.io
import std.subprocess
import std.fs
def main() async -> i32 {
    // A file the parent opened is not passed to children.
    var file: File? = nil;
    unsafe { file = File.open("subprocess.rl", 0); }
    let inherited = await Command.new("/bin/sh").arg("-c").arg("for n in 3 4 5 6 7 8 9; do if [ -e /dev/fd/$n ]; then printf \"$n \"; fi; done; echo done").output();
    println(inherited.ok_value()?.stdout.trim() ?? "?");
    switch await run("echo", ["hello", "world"]) {
        case .ok(let r): println(f"[{r.stdout.trim()}] {r.status} {r.status.success()}");
        case .err(let e): println(e.to_string());
    }
    switch await shell("echo out; echo err 1>&2; exit 3") {
        case .ok(let r): println(f"[{r.stdout.trim()}] [{r.stderr.trim()}] {r.status}");
        case .err(let e): println(e.to_string());
    }
    switch await run("no-such-program-xyz") { case .ok(let r): println("??"); case .err(let e): println(e.to_string()); }
    guard let child = Command.new("sort").stdin(Stdio.piped).stdout(Stdio.piped).spawn().ok_value() else { return 1; }
    await child.write("pear\napple\nfig\n");
    switch await child.output() { case .ok(let r): println(r.stdout.replace("\n", ",")); case .err(let e): println(e.to_string()); }
    let env = await Command.new("/bin/sh").arg("-c").arg("echo $GREETING-$HOME").env("GREETING", "hi").env_clear().output();
    println((env.ok_value()?.stdout ?? "?").trim());
    let dir = await Command.new("pwd").current_dir("/").output();
    println((dir.ok_value()?.stdout ?? "?").trim());
    guard let sleeper = Command.new("sleep").arg("10").spawn().ok_value() else { return 2; }
    println(f"{sleeper.pid > 0} {sleeper.kill()}");
    let status = await sleeper.wait();
    println(f"{status} {status.success()} {sleeper.kill()}");
    let big = await shell("head -c 1000000 /dev/zero | tr '\\0' 'x'; head -c 300000 /dev/zero | tr '\\0' 'y' 1>&2");
    if let r = big.ok_value() { println(f"{r.stdout.len()} {r.stderr.len()}"); }
    0
}
