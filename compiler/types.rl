// Type identities, interning and queries. Display names never determine identity.
pub import "type_data.rl"
import "symbols.rl"
import "members.rl"
import std.string_builder

// Formats a defect detected after type checking, as opposed to an error in the program.
pub def internal_compiler_error(message: String) -> String { "internal compiler error: " + message + " (this is a compiler bug; please report it)" }
pub struct TypeTable {
    let types: Vec<TypeInfo>;
    let builtins: Dict<String, TypeId>;
    let intern_cache: Dict<String, TypeId>;
    var next_type_var_id: i32;
    var symbol_table: SymbolTable?;
    let member_cache: Dict<i32, TypeMembers>;
    let generic_param_names: Dict<i32, FrozenVec<String>>;
    let descriptors: Dict<i32, TypeDescriptorEntry>;
    // Associated type bindings ("<concrete type id>:<name>"), recorded when a type conforms.
    let associated: Dict<String, TypeId>;
    pub var error_type: TypeId;
    pub var never_type: TypeId;
    pub var void_type: TypeId;
    pub var nil_type: TypeId;

    pub static def new() -> TypeTable {
        let invalid = TypeId { id: -1 };
        let table = TypeTable {
            types: Vec<TypeInfo>.new(), builtins: Dict<String, TypeId>.with_capacity(16, 1),
            intern_cache: Dict<String, TypeId>.with_capacity(32, 1),
            next_type_var_id: 0, symbol_table: nil,
            member_cache: Dict<i32, TypeMembers>.with_capacity(16, 0),
            generic_param_names: Dict<i32, FrozenVec<String>>.with_capacity(16, 0),
            descriptors: Dict<i32, TypeDescriptorEntry>.with_capacity(16, 0),
            associated: Dict<String, TypeId>.with_capacity(16, 1),
            error_type: invalid, never_type: invalid, void_type: invalid, nil_type: invalid
        };
        let primitives = [PrimitiveType.i8(), PrimitiveType.i16(), PrimitiveType.i32(), PrimitiveType.i64(),
            PrimitiveType.u8(), PrimitiveType.u16(), PrimitiveType.u32(), PrimitiveType.u64(),
            PrimitiveType.f32(), PrimitiveType.f64(), PrimitiveType.bool_type(),
            PrimitiveType.void_type(), PrimitiveType.raw_ptr()];
        for primitive in primitives {
            let id = table.intern(TypeData.primitive(primitive));
            table.builtins[primitive.spelling()] = id;
            switch primitive { case .void_type: table.void_type = id; default: {} }
        }
        table.error_type = table.intern(TypeData.error());
        table.never_type = table.intern(TypeData.never());
        table.nil_type = table.intern(TypeData.type_variable(TypeVariableData {
            name: "__nil", id: table.types.len(), bounds: FrozenVec<TypeId>.empty()
        }));
        table
    }

    def append(data: TypeData) -> TypeId {
        let id = TypeId { id: self.types.len() };
        self.types.push(TypeInfo { id, kind: data.kind(), data });
        id
    }
    def intern(data: TypeData) -> TypeId {
        let key = data.key();
        if let id = self.intern_cache[key] { return id; }
        let id = self.append(data);
        self.intern_cache[key] = id;
        id
    }
    pub def get_type(type_id: TypeId) -> TypeInfo? {
        if type_id.id < 0 || type_id.id >= self.types.len() { return nil; }
        self.types[type_id.id]
    }
    pub def all_types() -> FrozenVec<TypeInfo> { FrozenVec<TypeInfo>.new(self.types) }
    pub def attach_symbol_table(symbol_table: SymbolTable) -> Void { self.symbol_table = symbol_table; }
    def symbol_name(symbol_id: SymbolId?, fallback_prefix: String) -> String {
        guard let id = symbol_id else { return f"{fallback_prefix}#anon"; }
        if let table = self.symbol_table {
            if let symbol = table.get_symbol(id) {
                if !symbol.name.is_empty() { return symbol.name; }
            }
        }
        f"{fallback_prefix}#{id.id}"
    }
    pub def get_builtin(name: String) -> TypeId? { self.builtins[name] }
    pub def is_error(type_id: TypeId) -> Bool { type_id == self.error_type }
    pub def is_never(type_id: TypeId) -> Bool { type_id == self.never_type }

    pub def make_struct(symbol_id: SymbolId, type_args: Vec<TypeId> = Vec<TypeId>.new()) -> TypeId {
        self.intern(TypeData.struct_type(StructTypeData {
            symbol_id, type_args: FrozenVec<TypeId>.new(type_args), anon_fields: nil
        }))
    }
    pub def make_enum(symbol_id: SymbolId, type_args: Vec<TypeId> = Vec<TypeId>.new()) -> TypeId {
        self.intern(TypeData.enum_type(EnumTypeData { symbol_id, type_args: FrozenVec<TypeId>.new(type_args) }))
    }
    pub def set_type_members(symbol_id: SymbolId, members: TypeMembers) -> Void { self.member_cache[symbol_id.id] = members; }
    pub def get_type_members(symbol_id: SymbolId) -> TypeMembers? { self.member_cache[symbol_id.id] }
    pub def set_generic_param_names(symbol_id: SymbolId, names: Vec<String>) -> Void {
        self.generic_param_names[symbol_id.id] = FrozenVec<String>.new(names);
    }
    pub def get_generic_param_names(symbol_id: SymbolId) -> FrozenVec<String> {
        self.generic_param_names[symbol_id.id] ?? FrozenVec<String>.empty()
    }
    pub def make_tuple(elements: Vec<(String?, TypeId)>) -> TypeId {
        let fields = Vec<TupleField>.new();
        for i in 0..<elements.len() {
            let element = elements[i];
            fields.push(TupleField { name: element.0 ?? i.to_string(), type_id: element.1 });
        }
        self.intern(TypeData.struct_type(StructTypeData {
            symbol_id: nil, type_args: FrozenVec<TypeId>.empty(), anon_fields: FrozenVec<TupleField>.new(fields)
        }))
    }
    pub def make_function(params: Vec<TypeId>, return_type: TypeId, is_async: Bool = false) -> TypeId {
        self.intern(TypeData.function(FunctionTypeData { params: FrozenVec<TypeId>.new(params), return_type, is_async }))
    }
    pub def make_optional(inner: TypeId) -> TypeId { self.intern(TypeData.optional(inner)) }
    pub def make_type_variable(name: String, bounds: Vec<TypeId> = Vec<TypeId>.new()) -> TypeId {
        let id = self.next_type_var_id;
        self.next_type_var_id += 1;
        // Fresh type variables deliberately bypass interning.
        self.append(TypeData.type_variable(TypeVariableData { name, id, bounds: FrozenVec<TypeId>.new(bounds) }))
    }
    pub def make_closure(params: Vec<TypeId>, return_type: TypeId, captures: Vec<TypeId>, is_async: Bool = false) -> TypeId {
        self.intern(TypeData.closure(ClosureTypeData {
            params: FrozenVec<TypeId>.new(params), return_type,
            captures: FrozenVec<TypeId>.new(captures), is_async
        }))
    }
    pub def make_protocol(symbol_id: SymbolId, func_requirements: Vec<FuncRequirement> = Vec<FuncRequirement>.new(),
                          prop_requirements: Vec<PropRequirement> = Vec<PropRequirement>.new()) -> TypeId {
        self.intern(TypeData.protocol(ProtocolTypeData { symbol_id,
            func_requirements: FrozenVec<FuncRequirement>.new(func_requirements),
            prop_requirements: FrozenVec<PropRequirement>.new(prop_requirements)
        }))
    }
    pub def make_existential(protocol_id: TypeId) -> TypeId {
        self.intern(TypeData.existential(ExistentialTypeData { protocol_id }))
    }

    def primitive(type_id: TypeId) -> PrimitiveType? {
        guard let info = self.get_type(type_id) else { return nil; }
        switch info.data { case .primitive(let primitive): primitive; default: nil; }
    }
    pub def is_integer(type_id: TypeId) -> Bool {
        guard let primitive = self.primitive(type_id) else { return false; }
        primitive.integer_width() > 0
    }
    pub def is_signed_integer(type_id: TypeId) -> Bool {
        guard let primitive = self.primitive(type_id) else { return false; }
        primitive.is_signed()
    }
    pub def is_float(type_id: TypeId) -> Bool {
        guard let primitive = self.primitive(type_id) else { return false; }
        primitive.is_float()
    }
    pub def is_numeric(type_id: TypeId) -> Bool { self.is_integer(type_id) || self.is_float(type_id) }
    pub def can_widen_int(source: TypeId, target: TypeId) -> Bool {
        guard let src = self.primitive(source) else { return false; }
        guard let dst = self.primitive(target) else { return false; }
        src.integer_width() > 0 && src.integer_width() < dst.integer_width() &&
            (src.is_signed() == dst.is_signed() || !src.is_signed())
    }
    pub def is_bool(type_id: TypeId) -> Bool {
        guard let primitive = self.primitive(type_id) else { return false; }
        switch primitive { case .bool_type: true; default: false; }
    }
    pub def has_type_variables(type_id: TypeId) -> Bool {
        guard let info = self.get_type(type_id) else { return false; }
        switch info.data {
            case .type_variable(_): return true;
            case .struct_type(let data):
                for arg in data.type_args { if self.has_type_variables(arg) { return true; } }
                if let fields = data.anon_fields {
                    for field in fields { if self.has_type_variables(field.type_id) { return true; } }
                }
            case .enum_type(let data):
                for arg in data.type_args { if self.has_type_variables(arg) { return true; } }
            case .optional(let inner): return self.has_type_variables(inner);
            case .function(let data):
                for param in data.params { if self.has_type_variables(param) { return true; } }
                return self.has_type_variables(data.return_type);
            // This query does not traverse closure or protocol payloads.
            default: {}
        }
        false
    }
    pub def is_string(type_id: TypeId) -> Bool {
        guard let info = self.get_type(type_id) else { return false; }
        switch info.data { case .struct_type(_): self.format_type(type_id).starts_with("String"); default: false; }
    }
    pub def is_optional(type_id: TypeId) -> Bool {
        if let inner = self.get_optional_inner(type_id) { return true; }
        false
    }
    pub def get_optional_inner(type_id: TypeId) -> TypeId? {
        guard let info = self.get_type(type_id) else { return nil; }
        switch info.data { case .optional(let inner): inner; default: nil; }
    }
    pub def set_descriptor(type_id: TypeId, desc: TypeDescriptorEntry) -> Void { self.descriptors[type_id.id] = desc; }
    pub def get_descriptor(type_id: TypeId) -> TypeDescriptorEntry? { self.descriptors[type_id.id] }
    pub def get_all_descriptors() -> Dict<i32, TypeDescriptorEntry> {
        let result = Dict<i32, TypeDescriptorEntry>.with_capacity(16, 0);
        for entry in self.descriptors.entries() { result[entry.key] = entry.value; }
        result
    }
    pub def is_heap_type(type_id: TypeId) -> Bool {
        guard let info = self.get_type(type_id) else { return false; }
        switch info.data { case .struct_type(_) | .enum_type(_) | .closure(_) | .existential(_): true; default: false; }
    }
    // Nonzero when runtime containers must retain/release values of this type. Function
    // values are closure objects, so they are managed like heap types.
    pub def runtime_type_id(type_id: TypeId) -> i32 {
        if self.is_heap_type(type_id) || self.is_function(type_id) { return 1; }
        if let inner = self.get_optional_inner(type_id) { if self.is_heap_type(inner) || self.is_function(inner) { return 1; } }
        0
    }
    pub def is_function(type_id: TypeId) -> Bool {
        if let data = self.get_function_data(type_id) { return true; }
        false
    }
    pub def get_function_data(type_id: TypeId) -> FunctionTypeData? {
        guard let info = self.get_type(type_id) else { return nil; }
        switch info.data { case .function(let data): data; default: nil; }
    }
    pub def is_closure(type_id: TypeId) -> Bool {
        if let data = self.get_closure_data(type_id) { return true; }
        false
    }
    pub def get_closure_data(type_id: TypeId) -> ClosureTypeData? {
        guard let info = self.get_type(type_id) else { return nil; }
        switch info.data { case .closure(let data): data; default: nil; }
    }
    pub def is_callable(type_id: TypeId) -> Bool { self.is_function(type_id) || self.is_closure(type_id) }
    pub def is_protocol(type_id: TypeId) -> Bool {
        if let data = self.get_protocol_data(type_id) { return true; }
        false
    }
    pub def get_protocol_data(type_id: TypeId) -> ProtocolTypeData? {
        guard let info = self.get_type(type_id) else { return nil; }
        switch info.data { case .protocol(let data): data; default: nil; }
    }
    pub def is_existential(type_id: TypeId) -> Bool {
        if let data = self.get_existential_data(type_id) { return true; }
        false
    }
    pub def get_existential_data(type_id: TypeId) -> ExistentialTypeData? {
        guard let info = self.get_type(type_id) else { return nil; }
        switch info.data { case .existential(let data): data; default: nil; }
    }
    pub def get_protocol_type(symbol_id: SymbolId) -> TypeId {
        for info in self.types {
            switch info.data {
                case .protocol(let data): if data.symbol_id == symbol_id { return info.id; }
                default: {}
            }
        }
        self.make_protocol(symbol_id)
    }

    def format_types(types: FrozenVec<TypeId>) -> String {
        join_type_names(types.map((type) -> { self.format_type(type) }))
    }
    def format_named(symbol_id: SymbolId, prefix: String, args: FrozenVec<TypeId>) -> String {
        let name = self.symbol_name(symbol_id, prefix);
        if args.len() == 0 { return name; }
        f"{name}<{self.format_types(args)}>"
    }
    pub def format_type(type_id: TypeId) -> String {
        guard let info = self.get_type(type_id) else { return "<unknown>"; }
        switch info.data {
            case .primitive(let primitive): return primitive.spelling();
            case .struct_type(let data):
                if let id = data.symbol_id { return self.format_named(id, "struct", data.type_args); }
                var text = "";
                if let fields = data.anon_fields {
                    for field in fields {
                        if !text.is_empty() { text += ", "; }
                        if !numeric_label(field.name) { text += f"{field.name}: "; }
                        text += self.format_type(field.type_id);
                    }
                }
                return f"({text})";
            case .enum_type(let data): return self.format_named(data.symbol_id, "enum", data.type_args);
            case .function(let data):
                let prefix = if_async(data.is_async);
                return f"{prefix}({self.format_types(data.params)}) -> {self.format_type(data.return_type)}";
            case .optional(let inner): return f"{self.format_type(inner)}?";
            case .closure(let data):
                let prefix = if_async(data.is_async);
                return f"{prefix}closure({self.format_types(data.params)}) -> {self.format_type(data.return_type)} [captures: {self.format_types(data.captures)}]";
            case .protocol(let data): return self.symbol_name(data.symbol_id, "protocol");
            case .existential(let data): return f"any {self.format_type(data.protocol_id)}";
            case .type_variable(let data): return f"${data.name}";
            case .error: return "<error>";
            case .never: return "Never";
        }
    }
    pub def bind_associated(concrete: TypeId, name: String, type: TypeId) -> Void { self.associated[f"{concrete.id}:{name}"] = type; }
    pub def associated_type(concrete: TypeId, name: String) -> TypeId? { self.associated[f"{concrete.id}:{name}"] }
    // Substitutes a projection type variable such as `C.Item` once `C` is mapped: a concrete
    // base yields its associated type binding, another type variable `D` yields `D.Item`.
    pub def project(name: String, mapping: Dict<String, TypeId>) -> TypeId? {
        let dot = name.find(".");
        if dot <= 0 { return nil; }
        guard let base = mapping[name.substring(0, dot)] else { return nil; }
        let member = name.substring(dot + 1, (name.len() as i32) - dot - 1);
        if let info = self.get_type(base) { switch info.data { case .type_variable(let data): return self.make_type_variable(data.name + "." + member); default: {} } }
        self.associated_type(base, member)
    }
    // Structural type equality; type variables compare by name.
    pub def types_equal(left: TypeId, right: TypeId) -> Bool {
        if left == right { return true; }
        guard let a = self.get_type(left) else { return false; }
        guard let b = self.get_type(right) else { return false; }
        switch a.data {
            case .type_variable(let x): switch b.data { case .type_variable(let y): return x.name.equals(y.name); default: {} }
            case .optional(let x): switch b.data { case .optional(let y): return self.types_equal(x, y); default: {} }
            case .struct_type(let x):
                switch b.data {
                    case .struct_type(let y):
                        if let symbol = x.symbol_id {
                            if let other = y.symbol_id { return symbol == other && self.equal_list(x.type_args, y.type_args); }
                        } else {
                            if let other = y.symbol_id { return false; }
                            let xf = x.anon_fields ?? FrozenVec<TupleField>.empty(); let yf = y.anon_fields ?? FrozenVec<TupleField>.empty();
                            if xf.len() != yf.len() { return false; }
                            for index in 0..<xf.len() { if !self.types_equal(xf.get(index).type_id, yf.get(index).type_id) { return false; } }
                            return true;
                        }
                    default: {}
                }
            case .enum_type(let x): switch b.data { case .enum_type(let y): return x.symbol_id == y.symbol_id && self.equal_list(x.type_args, y.type_args); default: {} }
            case .function(let x): switch b.data { case .function(let y): return x.is_async == y.is_async && self.equal_list(x.params, y.params) && self.types_equal(x.return_type, y.return_type); default: {} }
            case .closure(let x): switch b.data { case .closure(let y): return x.is_async == y.is_async && self.equal_list(x.params, y.params) && self.equal_list(x.captures, y.captures) && self.types_equal(x.return_type, y.return_type); default: {} }
            default: {}
        }
        false
    }
    def equal_list(left: FrozenVec<TypeId>, right: FrozenVec<TypeId>) -> Bool {
        if left.len() != right.len() { return false; }
        for index in 0..<left.len() { if !self.types_equal(left.get(index), right.get(index)) { return false; } }
        true
    }
}

def if_async(value: Bool) -> String { if value { return "async "; } "" }
def join_type_names(names: FrozenVec<String>) -> String {
    let result = StringBuilder.new();
    var first = true;
    for name in names {
        if !first { result.append(", "); }
        result.append(name); first = false;
    }
    result.to_string()
}
def numeric_label(name: String) -> Bool {
    if name.is_empty() { return false; }
    for i in 0..<(name.len() as i32) {
        let ch = name.byte_at(i);
        if ch < 48 || ch > 57 { return false; }
    }
    true
}
