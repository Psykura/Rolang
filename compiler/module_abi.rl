// Versioned native module identities. Allocation-order IDs never cross an object
// boundary. Length-prefixed atoms make names, paths and recursive types unambiguous.
pub import "types.rl"
pub import "symbols.rl"
pub import "ast.rl"
import "build_cache.rl"
import std.sha256

pub def module_abi_version() -> String { "rolang-abi-1" }
pub def mark_module_declarations(arena: AstArena, root: NodeId, symbols: SymbolTable, owner: String, source: String) -> Void {
    let prefix = encode_records([owner, sha256(source)]); var index = 0;
    for node in arena.preorder(root) {
        symbols.abi_nodes[node.id] = prefix + encode_records([index.to_string()]);
        symbols.abi_owners[node.id] = owner; index += 1;
    }
}
pub def abi_symbol_owner(id: SymbolId, symbols: SymbolTable) -> String {
    if let origin = symbols.specialization_origin[id.id] { return abi_symbol_owner(origin.original_id, symbols); }
    if let symbol = symbols.get_symbol(id) { if let node = symbol.decl_node { return symbols.abi_owners[node.id] ?? ""; } }
    ""
}
pub def abi_symbol_key(id: SymbolId, symbols: SymbolTable, types: TypeTable) -> String {
    if let origin = symbols.specialization_origin[id.id] {
        let key = abi_symbol_key(origin.original_id, symbols, types);
        if key.len() == 0 { return ""; }
        let parts = ["specialization", key];
        for arg in origin.type_args { parts.push(abi_type_key(arg, symbols, types)); }
        return encode_records(parts);
    }
    if let synthetic = symbols.module_type_keys[id.id] { return synthetic; }
    if let symbol = symbols.get_symbol(id) {
        if let node = symbol.decl_node { if let key = symbols.abi_nodes[node.id] { return key; } }
        if let builtin = symbols.builtins[symbol.name] { if builtin == id { return encode_records(["builtin", symbol.name]); } }
    }
    ""
}
pub def abi_type_key(id: TypeId, symbols: SymbolTable, types: TypeTable) -> String {
    guard let info = types.get_type(id) else { return encode_records(["invalid"]); }
    let parts = Vec<String>.new();
    switch info.data {
        case .primitive(let value): parts.push("primitive"); parts.push(value.spelling());
        case .struct_type(let data):
            parts.push("struct");
            if let symbol = data.symbol_id { parts.push("named"); parts.push(abi_symbol_key(symbol, symbols, types)); }
            else { parts.push("anonymous"); }
            parts.push(data.type_args.len().to_string());
            for arg in data.type_args { parts.push(abi_type_key(arg, symbols, types)); }
            if let fields = data.anon_fields { parts.push("fields");
                for field in fields { parts.push(field.name); parts.push(abi_type_key(field.type_id, symbols, types)); }
            } else { parts.push("no-fields"); }
        case .enum_type(let data):
            parts.push("enum"); parts.push(abi_symbol_key(data.symbol_id, symbols, types));
            for arg in data.type_args { parts.push(abi_type_key(arg, symbols, types)); }
        case .function(let data):
            parts.push("function"); parts.push(data.is_async.to_string()); parts.push(abi_type_key(data.return_type, symbols, types));
            for param in data.params { parts.push(abi_type_key(param, symbols, types)); }
        case .closure(let data):
            parts.push("closure"); parts.push(data.is_async.to_string()); parts.push(abi_type_key(data.return_type, symbols, types));
            parts.push(data.params.len().to_string());
            for param in data.params { parts.push(abi_type_key(param, symbols, types)); }
            for capture in data.captures { parts.push(abi_type_key(capture, symbols, types)); }
        case .optional(let inner): parts.push("optional"); parts.push(abi_type_key(inner, symbols, types));
        // A named protocol's source identity includes its complete declaration;
        // expanding Self requirements here would introduce recursive keys.
        case .protocol(let data):
            parts.push("protocol"); parts.push(abi_symbol_key(data.symbol_id, symbols, types));
            for arg in data.arguments { parts.push(abi_type_key(arg, symbols, types)); }
        case .existential(let data): parts.push("existential"); parts.push(abi_type_key(data.protocol_id, symbols, types));
        case .type_variable(let data): parts.push("variable"); parts.push(data.name);
        case .error: parts.push("error"); case .never: parts.push("never");
    }
    encode_records(parts)
}
pub def abi_descriptor_id(key: String) -> i64 {
    let hash = sha256(key); var value: i64 = 0;
    // 60 hash bits plus the sparse-ID marker; the result fits signed i64.
    for i in 0..<15 { let ch = hash.byte_at(i); var digit = ch - 48;
        if ch >= 97 { digit = ch - 87; } value = value * 16 + (digit as i64);
    }
    value | 4611686018427387904
}
pub def abi_async_name(symbol: SymbolId, fallback: String, symbols: SymbolTable, types: TypeTable) -> String {
    if !symbols.separate_modules || fallback.equals("main") { return fallback; }
    let key = abi_symbol_key(symbol, symbols, types);
    if key.len() == 0 { return fallback; }
    "__rl_async_" + sha256(key)
}
pub def abi_async_method_name(symbol: SymbolId, receiver: TypeId, fallback: String, symbols: SymbolTable, types: TypeTable) -> String {
    if !symbols.separate_modules { return fallback; }
    var original = symbol;
    // Methods on instantiated owners can retain the original method SymbolId
    // in HIR. Recover the emitted specialization, including empty owner args.
    if let origin = symbols.specialization_origin[symbol.id] {
        if origin.type_args.len() > 0 { return abi_async_name(symbol, fallback, symbols, types); }
        original = origin.original_id;
    }
    var args = Vec<TypeId>.new(); var owner: SymbolId? = nil;
    if let info = types.get_type(receiver) { switch info.data {
        case .struct_type(let data): owner = data.symbol_id; args = data.type_args.to_vec();
        case .enum_type(let data): owner = data.symbol_id; args = data.type_args.to_vec();
        default: {}
    } }
    if args.len() == 0 { if let id = owner { if let origin = symbols.specialization_origin[id.id] { args = origin.type_args.to_vec(); } } }
    if let actual = symbols.find_specialization(original, args) { return abi_async_name(actual, fallback, symbols, types); }
    abi_async_name(symbol, fallback, symbols, types)
}
