import "range.rl"
// Standard library: path manipulation
import "vec.rl"
import "string.rl"

pub extern "C" def rt_path_join_handle(a: String, b: String) -> RawPtr;
pub extern "C" def rt_path_dirname_handle(p: String) -> RawPtr;
pub extern "C" def rt_path_basename_handle(p: String) -> RawPtr;
pub extern "C" def rt_path_extension_handle(p: String) -> RawPtr;
pub extern "C" def rt_path_exists_string(p: String) -> i32;
pub extern "C" def rt_path_is_dir_string(p: String) -> i32;
pub extern "C" def rt_path_is_file_string(p: String) -> i32;
pub extern "C" def rt_path_resolve_handle(p: String) -> RawPtr;
pub extern "C" def rt_dir_list_handles(path: String) -> RawPtr;

pub def path_join(a: String, b: String) -> String {
    unsafe { return String.from_handle(rt_path_join_handle(a, b)); }
}
pub def path_dirname(p: String) -> String {
    unsafe { return String.from_handle(rt_path_dirname_handle(p)); }
}
pub def path_basename(p: String) -> String {
    unsafe { return String.from_handle(rt_path_basename_handle(p)); }
}
pub def path_extension(p: String) -> String {
    unsafe { return String.from_handle(rt_path_extension_handle(p)); }
}
pub def path_exists(p: String) -> Bool {
    unsafe { return rt_path_exists_string(p) != 0; }
}
pub def path_is_dir(p: String) -> Bool {
    unsafe { return rt_path_is_dir_string(p) != 0; }
}
pub def path_is_file(p: String) -> Bool {
    unsafe { return rt_path_is_file_string(p) != 0; }
}
pub def path_resolve(p: String) -> String {
    unsafe { return String.from_handle(rt_path_resolve_handle(p)); }
}

pub def dir_list(path: String) -> Vec<String>? {
    unsafe {
        let handle = rt_dir_list_handles(path);
        if handle as i64 == 0 { return nil; }
        let n = rt_gvec_len(handle);
        var out = Vec<String>.with_capacity(n);
        for i in 0..<n {
            var entry_handle: RawPtr;
            rt_gvec_get(handle, i, entry_handle as RawPtr);
            out.push(String.from_handle(entry_handle));
        }
        rt_gvec_free(handle);
        return out;
    }
}
