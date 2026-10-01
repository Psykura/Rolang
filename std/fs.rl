// Standard library: file system I/O
import "string.rl"

pub extern "C" def rt_file_open_handle(path: String, mode: i32) -> RawPtr;
pub extern "C" def rt_file_close(file: RawPtr) -> Void;
pub extern "C" def rt_file_read(file: RawPtr, buf: RawPtr, size: i32) -> i32;
pub extern "C" def rt_file_write(file: RawPtr, buf: RawPtr, size: i32) -> i32;
pub extern "C" def rt_file_read_all_handle(file: RawPtr) -> RawPtr;
pub extern "C" def rt_file_read_line_handle(file: RawPtr) -> RawPtr;
pub extern "C" def rt_file_write_string(file: RawPtr, s: String) -> i32;
pub extern "C" def rt_file_seek(file: RawPtr, offset: i64, whence: i32) -> i32;
pub extern "C" def rt_file_tell(file: RawPtr) -> i64;
pub extern "C" def rt_file_flush(file: RawPtr) -> i32;
pub extern "C" def rt_file_eof(file: RawPtr) -> i32;
pub extern "C" def rt_file_read_checked_handle(path: String, limit: i64) -> RawPtr;
pub extern "C" def rt_file_write_atomic(path: String, text: String, mode: i32) -> i32;
pub extern "C" def rt_file_copy_atomic(from: String, to: String, mode: i32) -> i32;
pub extern "C" def rt_file_move(from: String, to: String) -> i32;
pub extern "C" def rt_file_mode(path: String) -> i32;
pub extern "C" def rt_file_size_checked(path: String) -> i64;
pub extern "C" def rt_path_mkdirs(path: String) -> i32;
pub extern "C" def rt_path_remove(path: String) -> i32;
pub extern "C" def rt_temp_dir_handle(pattern: String) -> RawPtr;

pub struct File {
    var handle: RawPtr;

    pub unsafe static def open(path: String, mode: i32) -> File? {
        unsafe {
            let h = rt_file_open_handle(path, mode);
            if (h as i64) == 0 { return nil; }
            return File { handle: h };
        }
    }

    pub def close() -> Void {
        unsafe { rt_file_close(self.handle); }
    }
    pub def read(buf: RawPtr, size: i32) -> i32 {
        unsafe { return rt_file_read(self.handle, buf, size); }
    }
    pub def write(buf: RawPtr, size: i32) -> i32 {
        unsafe { return rt_file_write(self.handle, buf, size); }
    }
    pub def read_all() -> String {
        unsafe { return String.from_handle(rt_file_read_all_handle(self.handle)); }
    }
    pub def read_line() -> String {
        unsafe { return String.from_handle(rt_file_read_line_handle(self.handle)); }
    }
    pub def seek(offset: i64, whence: i32) -> i32 {
        unsafe { return rt_file_seek(self.handle, offset, whence); }
    }
    pub def tell() -> i64 {
        unsafe { return rt_file_tell(self.handle); }
    }
    pub def flush() -> i32 {
        unsafe { return rt_file_flush(self.handle); }
    }
    pub def eof() -> i32 {
        unsafe { return rt_file_eof(self.handle); }
    }
}

pub def fs_open(path: String, mode: i32) -> RawPtr { unsafe { return rt_file_open_handle(path, mode); } }
pub def fs_close(file: RawPtr) -> Void { unsafe { rt_file_close(file); } }
pub def fs_read(file: RawPtr, buf: RawPtr, size: i32) -> i32 { unsafe { return rt_file_read(file, buf, size); } }
pub def fs_write(file: RawPtr, buf: RawPtr, size: i32) -> i32 { unsafe { return rt_file_write(file, buf, size); } }
pub def fs_read_all(file: RawPtr) -> String { unsafe { return String.from_handle(rt_file_read_all_handle(file)); } }
pub def fs_read_line(file: RawPtr) -> String { unsafe { return String.from_handle(rt_file_read_line_handle(file)); } }
pub def fs_write_str(file: RawPtr, s: String) -> i32 { unsafe { return rt_file_write_string(file, s); } }
pub def fs_seek(file: RawPtr, offset: i64, whence: i32) -> i32 { unsafe { return rt_file_seek(file, offset, whence); } }
pub def fs_tell(file: RawPtr) -> i64 { unsafe { return rt_file_tell(file); } }
pub def fs_flush(file: RawPtr) -> i32 { unsafe { return rt_file_flush(file); } }
pub def fs_eof(file: RawPtr) -> i32 { unsafe { return rt_file_eof(file); } }

// Checked reads distinguish an empty file from failure and bound allocation.
pub def fs_read_text(path: String, limit: i64 = 536870912) -> String? {
    unsafe {
        let handle = rt_file_read_checked_handle(path, limit);
        if (handle as i64) == 0 { return nil; }
        return String.from_handle(handle);
    }
}
pub def fs_write_atomic(path: String, text: String, mode: i32 = 420) -> Bool {
    unsafe { return rt_file_write_atomic(path, text, mode) == 0; }
}
// mode=-1 preserves the source's permission bits.
pub def fs_copy_atomic(from: String, to: String, mode: i32 = -1) -> Bool {
    unsafe { return rt_file_copy_atomic(from, to, mode) == 0; }
}
pub def fs_move(from: String, to: String) -> Bool { unsafe { return rt_file_move(from, to) == 0; } }
pub def fs_mode(path: String) -> i32 { unsafe { return rt_file_mode(path); } }
pub def fs_size(path: String) -> i64 { unsafe { return rt_file_size_checked(path); } }
pub def fs_mkdirs(path: String) -> Bool { unsafe { return rt_path_mkdirs(path) == 0; } }
// Removes one file/symlink or an empty directory, without following links.
pub def fs_remove(path: String) -> Bool { unsafe { return rt_path_remove(path) == 0; } }
pub def fs_temp_dir(pattern: String) -> String? {
    unsafe {
        let handle = rt_temp_dir_handle(pattern);
        if (handle as i64) == 0 { return nil; }
        return String.from_handle(handle);
    }
}
