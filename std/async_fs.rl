// Standard library: file operations that do not block other tasks.
//
//     switch await read_file("config.toml") {
//         case .ok(let text): ...
//         case .err(let error): eprintln(error.to_string());   // "config.toml: No such file or directory"
//     }
//     await write_file_atomic("state.json", json);
//
// Each operation runs on a small pool of worker threads while the calling
// task waits, so other tasks keep running. Errors carry the operating
// system's errno and message.
import "task.rl"
import "string.rl"
import "result.rl"
import "vec.rl"
import "async_io.rl"
import "time.rl"

pub extern "C" def rt_fs_start(op: i32, path: String, other: String, input: String, limit: i64, flags: i64) -> RawPtr;
pub extern "C" def rt_fs_error(task: RawPtr) -> i32;
pub extern "C" def rt_fs_output(task: RawPtr) -> RawPtr;
pub extern "C" def rt_fs_value(task: RawPtr, index: i32) -> i64;

pub struct FsError {
    pub let path: String;
    // The errno value.
    pub let code: i32;
    pub let message: String;
    pub def to_string() -> String { f"{self.path}: {self.message}" }
}

pub enum FileKind { case file; case directory; case symlink; case other; }

pub struct FileInfo {
    pub let size: i64;
    // Permission bits, e.g. 0o644.
    pub let mode: i32;
    pub let modified: DateTime;
    pub let kind: FileKind;
    pub def is_file() -> Bool { switch self.kind { case .file: return true; default: return false; } }
    pub def is_dir() -> Bool { switch self.kind { case .directory: return true; default: return false; } }
}

// The file's contents; fails past `limit` bytes (EFBIG).
pub def read_file(path: String, limit: i64 = 536870912) async -> Result<String, FsError> {
    unsafe {
        let operation = Task<i32>.from_handle(rt_fs_start(1, path, "", "", limit, 0));
        let status = await operation;
        if status != 0 { return Result<String, FsError>.err(error: fs_error(path, rt_fs_error(operation.raw_handle()))); }
        return Result<String, FsError>.ok(value: String.from_handle(rt_fs_output(operation.raw_handle())));
    }
}

// Replaces the file's contents (creating it); the result is the byte count.
pub def write_file(path: String, data: String) async -> Result<i64, FsError> { await write_with(path, data, 0) }
// Adds to the end of the file (creating it).
pub def append_file(path: String, data: String) async -> Result<i64, FsError> { await write_with(path, data, 1) }
// Creates the file, failing with EEXIST when it already exists.
pub def create_file(path: String, data: String) async -> Result<i64, FsError> { await write_with(path, data, 2) }
// Replaces the file so readers see the old or the new contents, never a part:
// writes a temporary file beside it, flushes it to disk and renames it.
pub def write_file_atomic(path: String, data: String) async -> Result<i64, FsError> {
    unsafe {
        let operation = Task<i32>.from_handle(rt_fs_start(3, path, "", data, 0, 0));
        let status = await operation;
        if status != 0 { return Result<i64, FsError>.err(error: fs_error(path, rt_fs_error(operation.raw_handle()))); }
        return Result<i64, FsError>.ok(value: rt_fs_value(operation.raw_handle(), 5));
    }
}

def write_with(path: String, data: String, flags: i64) async -> Result<i64, FsError> {
    unsafe {
        let operation = Task<i32>.from_handle(rt_fs_start(2, path, "", data, 0, flags));
        let status = await operation;
        if status != 0 { return Result<i64, FsError>.err(error: fs_error(path, rt_fs_error(operation.raw_handle()))); }
        return Result<i64, FsError>.ok(value: rt_fs_value(operation.raw_handle(), 5));
    }
}

// Names in a directory (without "." and ".."), sorted.
pub def list_dir(path: String) async -> Result<Vec<String>, FsError> {
    unsafe {
        let operation = Task<i32>.from_handle(rt_fs_start(4, path, "", "", 0, 0));
        let status = await operation;
        if status != 0 { return Result<Vec<String>, FsError>.err(error: fs_error(path, rt_fs_error(operation.raw_handle()))); }
        let text = String.from_handle(rt_fs_output(operation.raw_handle()));
        let names = Vec<String>.new();
        if text.len() > 0 { for name in text.split("\0") { names.push(name); } }
        names.sort();
        return Result<Vec<String>, FsError>.ok(value: names);
    }
}

// Size, permissions, modification time and kind; symbolic links are followed.
pub def file_info(path: String) async -> Result<FileInfo, FsError> {
    unsafe {
        let operation = Task<i32>.from_handle(rt_fs_start(5, path, "", "", 0, 0));
        let status = await operation;
        // Each read goes through `operation`, which keeps the task and its results alive.
        if status != 0 { return Result<FileInfo, FsError>.err(error: fs_error(path, rt_fs_error(operation.raw_handle()))); }
        var kind = FileKind.other;
        let code = rt_fs_value(operation.raw_handle(), 4);
        if code == 1 { kind = FileKind.directory; } else if code == 2 { kind = FileKind.file; } else if code == 3 { kind = FileKind.symlink; }
        let modified = DateTime.from_unix_nanos(rt_fs_value(operation.raw_handle(), 2) * 1000000000 + rt_fs_value(operation.raw_handle(), 3));
        return Result<FileInfo, FsError>.ok(value: FileInfo { size: rt_fs_value(operation.raw_handle(), 0), mode: rt_fs_value(operation.raw_handle(), 1) as i32, modified, kind });
    }
}

// Whether something exists at `path`.
pub def exists(path: String) async -> Bool { (await file_info(path)).is_ok() }

// Removes a file, or an empty directory.
pub def remove(path: String) async -> Result<Bool, FsError> { await simple_op(6, path, "", 0) }
// Creates a directory; with `recursive`, also its missing parents (an existing directory is fine).
pub def create_dir(path: String, recursive: Bool = false) async -> Result<Bool, FsError> {
    var flags: i64 = 0; if recursive { flags = 1; }
    await simple_op(7, path, "", flags)
}
// Renames or moves within one file system, replacing the target.
pub def rename(from: String, to: String) async -> Result<Bool, FsError> { await simple_op(8, from, to, 0) }

def simple_op(op: i32, path: String, other: String, flags: i64) async -> Result<Bool, FsError> {
    unsafe {
        let operation = Task<i32>.from_handle(rt_fs_start(op, path, other, "", 0, flags));
        let status = await operation;
        if status != 0 { return Result<Bool, FsError>.err(error: fs_error(path, rt_fs_error(operation.raw_handle()))); }
        return Result<Bool, FsError>.ok(value: true);
    }
}

def fs_error(path: String, code: i32) -> FsError {
    var message = os_error_message(code);
    if code == 27 { message = "file too large for the read limit"; }
    FsError { path, code, message }
}
