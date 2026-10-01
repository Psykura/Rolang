// Rolang .rlm v1: bounded, byte-length-prefixed records, source/import metadata,
// native objects or LLVM bitcode, per-object SHA-256 and a whole-payload checksum.
pub import "build_cache.rl"
import std.sha256
import std.fs

pub struct ModuleSource {
    pub let text: String;
    pub let imports: Dict<String, String>;
}
pub struct ModuleArtifact {
    pub let entry: String;
    pub let sources: Dict<String, ModuleSource>;
    pub let objects: Dict<String, String>;
}
pub struct ModuleArtifactResult { pub let artifact: ModuleArtifact?; pub let error: String; pub let input_hash: String; }
def bad_artifact(error: String) -> ModuleArtifactResult { ModuleArtifactResult { artifact: nil, error, input_hash: "" } }
pub def valid_module_key(key: String) -> Bool {
    if key.contains("\0") { return false; }
    if key.starts_with("user:/") { return true; }
    if !key.starts_with("std:") || key.len() <= 4 { return false; }
    let path = key.substring(4, (key.len() - 4) as i32);
    if path.starts_with("/") { return false; }
    for part in path.split("/") { if part.equals("..") || part.equals(".") || part.len() == 0 { return false; } }
    true
}
def record_count(text: String) -> i32 {
    if text.len() == 0 || text.len() > 5 { return -1; }
    var count = 0;
    for i in 0..<(text.len() as i32) { let ch = text.byte_at(i); if ch < 48 || ch > 57 { return -1; } count = count * 10 + ch - 48; }
    if count > 65536 { return -1; } count
}
pub def read_module_artifact(path: String, target: String, compiler: String) -> ModuleArtifactResult {
    guard let text = fs_read_text(path, 134217728) else { return bad_artifact("cannot read archive or archive exceeds 128 MiB"); }
    guard let envelope = decode_records(text) else { return bad_artifact("invalid archive records"); }
    if envelope.len() != 3 || !envelope[0].equals("rolang-module-1") { return bad_artifact("unsupported native module format"); }
    if !valid_digest(envelope[1]) || !sha256(envelope[2]).equals(envelope[1]) { return bad_artifact("archive checksum mismatch"); }
    guard let records = decode_records(envelope[2]) else { return bad_artifact("invalid module records"); }
    if records.len() < 5 { return bad_artifact("incomplete module metadata"); }
    if !records[0].equals(compiler) { return bad_artifact("incompatible compiler ABI"); }
    if !records[1].equals(target) { return bad_artifact("module target does not match: " + records[1] + " / " + target); }
    let entry = records[2]; let source_count = record_count(records[3]); let object_count = record_count(records[4]);
    if source_count <= 0 || object_count <= 0 || records.len() != 5 + 3 * source_count + 3 * object_count { return bad_artifact("invalid module counts"); }
    let sources = Dict<String, ModuleSource>.with_capacity(16, 1); let objects = Dict<String, String>.with_capacity(16, 1);
    var index = 5;
    for i in 0..<source_count {
        let key = records[index]; let source = records[index+1];
        if !valid_module_key(key) || sources.contains(key) { return bad_artifact("invalid or duplicate source identity"); }
        guard let saved = decode_records(records[index+2]) else { return bad_artifact("invalid import metadata"); }
        if saved.len() % 2 != 0 { return bad_artifact("invalid import metadata"); }
        let imports = Dict<String, String>.with_capacity(16, 1); var next = 0;
        while next < saved.len() {
            if imports.contains(saved[next]) || !valid_module_key(saved[next+1]) { return bad_artifact("invalid or duplicate import identity"); }
            imports[saved[next]] = saved[next+1]; next += 2;
        }
        sources[key] = ModuleSource { text: source, imports }; index += 3;
    }
    for i in 0..<object_count {
        let key = records[index]; let hash = records[index+1]; let data = records[index+2];
        if !sources.contains(key) || objects.contains(key) || data.len() == 0 { return bad_artifact("invalid native object identity"); }
        if !valid_digest(hash) || !sha256(data).equals(hash) { return bad_artifact("native object checksum mismatch"); }
        objects[key] = data; index += 3;
    }
    if !sources.contains(entry) || !objects.contains(entry) { return bad_artifact("module entry has no source or native object"); }
    for record in sources.values() { for dependency in record.imports.values() {
        if !sources.contains(dependency) { return bad_artifact("module dependency source is missing"); }
        if dependency.starts_with("user:") && !objects.contains(dependency) { return bad_artifact("module dependency native object is missing"); }
    } }
    ModuleArtifactResult { artifact: ModuleArtifact { entry, sources, objects }, error: "", input_hash: sha256(text) }
}
pub def encode_module_artifact(artifact: ModuleArtifact, target: String, compiler: String) -> String {
    let records = [compiler, target, artifact.entry, artifact.sources.len().to_string(), artifact.objects.len().to_string()];
    for pair in artifact.sources.entries() {
        let imports = Vec<String>.new(); for imported in pair.value.imports.entries() { imports.push(imported.key); imports.push(imported.value); }
        records.push(pair.key); records.push(pair.value.text); records.push(encode_records(imports));
    }
    for pair in artifact.objects.entries() { records.push(pair.key); records.push(sha256(pair.value)); records.push(pair.value); }
    let payload = encode_records(records); encode_records(["rolang-module-1", sha256(payload), payload])
}
