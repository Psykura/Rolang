import std.io
import std.async_fs
import std.fs
import std.task
import std.result
def counter<T>(stop: Task<T>) async -> i32 {
    var ticks = 0;
    while !stop.done() { ticks += 1; await yield_now(); }
    ticks
}
def main() async -> i32 {
    guard let dir = fs_temp_dir("rolang-afs-XXXXXX") else { return 1; }
    let file = dir + "/a.txt";
    println(f"{(await write_file(file, "hello\n")).ok_value() ?? -1}");
    println(f"{(await append_file(file, "world\n")).ok_value() ?? -1}");
    println((await read_file(file)).ok_value()?.replace("\n", "|") ?? "?");
    println((await create_file(file, "x")).err_value()?.message ?? "created?");
    println(f"{(await write_file_atomic(dir + "/b.json", "{}")).ok_value() ?? -1}");
    println(f"{(await create_dir(dir + "/x/y/z", true)).is_ok()} {(await create_dir(dir + "/x")).err_value()?.message ?? "-"}");
    var names = ""; for name in (await list_dir(dir)).ok_value() ?? [] { names = names + name + " "; }
    println(names);
    if let info = (await file_info(file)).ok_value() { println(f"{info.size} {info.is_file()} {info.mode} {info.modified.year > 2000}"); }
    println(f"{(await file_info(dir + "/x")).ok_value()?.is_dir() ?? false} {await exists(dir + "/nope")}");
    println(f"{(await rename(file, dir + "/c.txt")).is_ok()} {(await read_file(dir + "/c.txt")).ok_value()?.len() ?? -1}");
    println((await read_file(dir + "/missing")).err_value()?.message ?? "?");
    println((await read_file(dir + "/c.txt", 3)).err_value()?.message ?? "?");
    println((await read_file(dir)).err_value()?.message ?? "?");
    println((await read_file("bad\0path")).err_value()?.message ?? "?");
    println(f"{(await remove(dir + "/x")).err_value()?.message ?? "-"}");
    // Other tasks run while a large file is written and read.
    let big = "z".repeat(50000000);
    let writer = spawn write_file(dir + "/big", big);
    let ticks = spawn counter(writer);
    let written = await writer;
    println(f"{written.ok_value() ?? -1} {await ticks > 0}");
    let reading = spawn read_file(dir + "/big");
    let ticks2 = spawn counter(reading);
    let data = await reading;
    println(f"{data.ok_value()?.len() ?? -1} {await ticks2 > 0}");
    // Many operations at once share the worker pool.
    let tasks = Vec<Task<Result<i64, FsError>>>.new();
    for index in 0..<50 { tasks.push(spawn write_file(f"{dir}/n{index}", f"{index}")); }
    var total: i64 = 0;
    for task in tasks { total += (await task).ok_value() ?? 0; }
    println(f"{total} {(await list_dir(dir)).ok_value()?.len() ?? -1}");
    for name in (await list_dir(dir)).ok_value() ?? [] {
        if name.equals("x") { continue; }
        await remove(dir + "/" + name);
    }
    await remove(dir + "/x/y/z"); await remove(dir + "/x/y"); await remove(dir + "/x"); await remove(dir);
    println(f"{await exists(dir)}");
    0
}
