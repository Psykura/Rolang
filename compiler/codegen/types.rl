// Backend storage layout follows LLVM/C alignment and the current runtime ABI.
// All managed values are header pointers; enum payloads follow a 32-bit tag.
pub import "../mir.rl"
pub import "ir.rl"
import "../module_abi.rl"

pub def llvm_align(value: i64, alignment: i64) -> i64 { ((value + alignment - 1) / alignment) * alignment }
pub struct LlvmField {
    pub let name: String;
    pub let type_id: TypeId;
    pub let offset: i64;
}
pub struct LlvmTypeCache {
    pub let types: TypeTable;
    pub let program: MirProgram;
    let structs: Dict<i32, MirStruct>;
    let enums: Dict<i32, MirEnum>;
    let field_cache: Dict<i32, Vec<LlvmField>>;
    let spelling_cache: Dict<i32, String>;
    pub let descriptor_types: Vec<TypeId>;
    let descriptor_ids: Dict<i32, i64>;
    let descriptor_keys: Dict<i64, String>;
    pub var symbols: SymbolTable?;
    pub let errors: Vec<String>;
    pub static def new(types: TypeTable, program: MirProgram) -> LlvmTypeCache {
        let cache = LlvmTypeCache { types, program,
            structs: Dict<i32, MirStruct>.with_capacity(16, 0), enums: Dict<i32, MirEnum>.with_capacity(16, 0),
            field_cache: Dict<i32, Vec<LlvmField>>.with_capacity(16, 0), spelling_cache: Dict<i32, String>.with_capacity(16, 0),
            descriptor_types: Vec<TypeId>.new(), descriptor_ids: Dict<i32, i64>.with_capacity(16, 0),
            descriptor_keys: Dict<i64, String>.with_capacity(16, 0), symbols: nil, errors: Vec<String>.new() };
        for item in program.structs { cache.structs[item.type_id.id] = item; }
        for item in program.enums { cache.enums[item.type_id.id] = item; }
        cache
    }
    pub def spelling(type_id: TypeId) -> String {
        if let cached = self.spelling_cache[type_id.id] { return cached; }
        var result = "void";
        if let info = self.types.get_type(type_id) { switch info.data {
            case .primitive(let primitive): switch primitive {
                case .bool_type: result = "i1"; case .raw_ptr: result = "ptr";
                case .f32: result = "float"; case .f64: result = "double";
                case .void_type: {} default: result = f"i{primitive.integer_width()}";
            }
            case .optional(let inner):
                let payload = self.spelling(inner);
                if payload.equals("ptr") { result = "ptr"; } else { result = "{ i1, " + payload + " }"; }
            case .struct_type | .enum_type | .closure | .function | .protocol | .existential: result = "ptr";
            default: {}
        } }
        self.spelling_cache[type_id.id] = result; result
    }
    pub def storage_size(type_id: TypeId) -> i64 {
        let type = self.spelling(type_id);
        if type.equals("ptr") || type.equals("double") { return 8; }
        if type.equals("float") { return 4; }
        let width = llvm_width(type); if width > 0 { if width == 1 { return 1; } return (width / 8) as i64; }
        if let inner = self.types.get_optional_inner(type_id) {
            let align = self.storage_align(inner); return llvm_align(llvm_align(1, align) + self.storage_size(inner), align);
        } 0
    }
    pub def storage_align(type_id: TypeId) -> i64 {
        if self.spelling(type_id).equals("ptr") { return 8; }
        if let inner = self.types.get_optional_inner(type_id) { return self.storage_align(inner); }
        let size = self.storage_size(type_id); if size < 1 { return 1; } size
    }
    pub def fields(type_id: TypeId) -> Vec<LlvmField> {
        if let cached = self.field_cache[type_id.id] { return cached; }
        let fields = Vec<LlvmField>.new(); var offset: i64 = 0;
        if let item = self.structs[type_id.id] {
            for field in item.fields {
                offset = llvm_align(offset, self.storage_align(field.type_id));
                fields.push(LlvmField { name: field.name, type_id: field.type_id, offset }); offset += self.storage_size(field.type_id);
            }
        } else if let info = self.types.get_type(type_id) { switch info.data {
            case .struct_type(let data): if let anonymous = data.anon_fields { for field in anonymous {
                offset = llvm_align(offset, self.storage_align(field.type_id));
                fields.push(LlvmField { name: field.name, type_id: field.type_id, offset }); offset += self.storage_size(field.type_id);
            } }
            case .closure(let data): offset = 8; for i in 0..<data.captures.len() {
                let capture = data.captures.get(i); offset = llvm_align(offset, self.storage_align(capture));
                fields.push(LlvmField { name: i.to_string(), type_id: capture, offset }); offset += self.storage_size(capture);
            }
            default: {}
        } }
        self.field_cache[type_id.id] = fields; fields
    }
    pub def field(type_id: TypeId, name: String) -> LlvmField? {
        for field in self.fields(type_id) { if field.name.equals(name) { return field; } } nil
    }
    pub def enum_case(type_id: TypeId, name: String) -> Vec<LlvmField> {
        let fields = Vec<LlvmField>.new(); var offset: i64 = 4;
        if let item = self.enums[type_id.id] { for case in item.cases { if case.name.equals(name) {
            // Alignment is relative to the union byte array after the i32 tag,
            // using the {i32, [N x i8]} body and descriptor offsets.
            var payload: i64 = 0;
            for i in 0..<case.payload_types.len() {
                let type_id = case.payload_types[i].1; payload = llvm_align(payload, self.storage_align(type_id));
                fields.push(LlvmField { name: i.to_string(), type_id, offset: offset + payload }); payload += self.storage_size(type_id);
            }
        } } } fields
    }
    pub def payload_size(type_id: TypeId) -> i64 {
        if let item = self.enums[type_id.id] {
            var size: i64 = 4;
            for case in item.cases { for field in self.enum_case(type_id, case.name) {
                let end = field.offset + self.storage_size(field.type_id); if end > size { size = end; }
            } } return size;
        }
        if let info = self.types.get_type(type_id) { switch info.data {
            case .struct_type | .closure:
                var size: i64 = 0; var alignment: i64 = 1;
                switch info.data { case .closure: size = 8; alignment = 8; default: {} }
                for field in self.fields(type_id) {
                    size = field.offset + self.storage_size(field.type_id);
                    let align = self.storage_align(field.type_id); if align > alignment { alignment = align; }
                }
                size = llvm_align(size, alignment); if size < 1 { size = 1; } return size;
            case .function: return 8;
            case .existential: return 16;
            default: {}
        } } self.storage_size(type_id)
    }
    pub def descriptor(type_id: TypeId) -> i64 {
        if let id = self.descriptor_ids[type_id.id] { return id; }
        var id = self.descriptor_types.len() as i64;
        if let symbols = self.symbols {
            let key = abi_type_key(type_id, symbols, self.types); id = abi_descriptor_id(key);
            if let previous = self.descriptor_keys[id] { if !previous.equals(key) { self.errors.push("Module ABI type hash collision"); } }
            self.descriptor_keys[id] = key;
        }
        self.descriptor_types.push(type_id); self.descriptor_ids[type_id.id] = id; id
    }
    pub def managed(type_id: TypeId) -> Bool {
        if self.types.is_heap_type(type_id) { return true; }
        if self.types.is_function(type_id) { return true; }
        if let inner = self.types.get_optional_inner(type_id) { return self.managed(inner); } false
    }
    pub def managed_inner(type_id: TypeId) -> TypeId {
        if let inner = self.types.get_optional_inner(type_id) { return self.managed_inner(inner); } type_id
    }
    pub def struct_name(type_id: TypeId) -> String? {
        if let item = self.structs[type_id.id] { return item.name; } nil
    }
    pub def frame(name: String) -> MirStruct? {
        for item in self.program.structs { if item.name.equals(name + "_Frame") { return item; } } nil
    }
}
