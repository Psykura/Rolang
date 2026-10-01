// Disposable native build cache. No executable metadata and no shell commands.
import std.fs
import std.path
import std.sha256
import std.string_builder
import std.collections

pub def absolute_path(path: String) -> String {
    if path.starts_with("/") { return path; }
    path_join(path_resolve("."), path)
}
pub def input_snapshot(path: String) -> String {
    let resolved = path_resolve(path);
    if path_is_file(path) {
        if let hash = file_sha256(path) { return resolved + "|file|" + hash; }
        return resolved + "|unreadable";
    }
    if path_is_dir(path) { return resolved + "|directory"; }
    resolved + "|missing"
}
pub def valid_digest(value: String) -> Bool {
    if value.len() != 64 { return false; }
    for i in 0..<64 { let ch = value.byte_at(i); if !((ch >= 48 && ch <= 57) || (ch >= 97 && ch <= 102)) { return false; } }
    true
}
pub def encode_records(records: Vec<String>) -> String {
    let out = StringBuilder.new();
    for value in records { out.append(value.len().to_string() + ":"); out.append(value); }
    out.to_string()
}
pub def decode_records(text: String) -> Vec<String>? {
    let out = Vec<String>.new(); var index = 0; let size = text.len() as i32;
    while index < size {
        var length = 0; var digits = 0;
        while index < size && text.byte_at(index) != 58 {
            let ch = text.byte_at(index); if ch < 48 || ch > 57 || digits >= 9 { return nil; }
            length = length * 10 + ch - 48; index += 1; digits += 1;
        }
        if digits == 0 || index >= size { return nil; }
        index += 1;
        if length > size - index || out.len() >= 65536 { return nil; }
        out.push(text.substring(index, length)); index += length;
    }
    out
}
pub struct BuildCache {
    let directory: String;
    let key: String;
    pub static def new(directory: String, context: Vec<String>) -> BuildCache {
        BuildCache { directory, key: sha256(encode_records(context)) }
    }
    def artifact() -> String { path_join(self.directory, self.key + ".artifact") }
    def index_path() -> String { path_join(self.directory, self.key + ".index") }
    pub def restore(output: String) -> Bool {
        guard let text = fs_read_text(self.index_path(), 4194304) else { return false; }
        guard let records = decode_records(text) else { return false; }
        if records.len() < 6 || records.len() % 2 != 0 { return false; }
        if !records[0].equals("rolang-cache-1") || !records[1].equals(self.key) || !valid_digest(records[2]) { return false; }
        let raw_mode = records[3]; if raw_mode.len() == 0 || raw_mode.len() > 3 { return false; }
        for i in 0..<(raw_mode.len() as i32) { let ch = raw_mode.byte_at(i); if ch < 48 || ch > 57 { return false; } }
        let mode = raw_mode.to_i32(); if mode < 0 || mode > 511 { return false; }
        var i = 4;
        while i < records.len() {
            if !records[i].starts_with("/") || !input_snapshot(records[i]).equals(records[i+1]) { return false; }
            i += 2;
        }
        let size = fs_size(self.artifact()); if size < 0 || size > 536870912 { return false; }
        guard let hash = file_sha256(self.artifact()) else { return false; }
        if !hash.equals(records[2]) { return false; }
        if fs_mode(output) == mode { if let existing = file_sha256(output) { if existing.equals(hash) { return true; } } }
        fs_copy_atomic(self.artifact(), output, mode)
    }
    pub def store(output: String, watches: Dict<String, String>) -> Void {
        if watches.len() == 0 { return; }
        let size = fs_size(output); if size < 0 || size > 536870912 { return; }
        for pair in watches.entries() { if !input_snapshot(pair.key).equals(pair.value) || pair.value.ends_with("|unreadable") { return; } }
        guard let hash = file_sha256(output) else { return; }
        let mode = fs_mode(output); if mode < 0 || mode > 511 { return; }
        if !fs_mkdirs(self.directory) { return; }
        let records = ["rolang-cache-1", self.key, hash, mode.to_string()];
        for pair in watches.entries() { records.push(pair.key); records.push(pair.value); }
        if !fs_copy_atomic(output, self.artifact(), mode) { return; }
        // The two atomic files can race: mismatched hashes cause a cache miss.
        fs_write_atomic(self.index_path(), encode_records(records), 384);
    }
}
