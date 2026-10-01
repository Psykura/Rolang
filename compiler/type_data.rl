// Immutable type payloads. FrozenVec stores ordered metadata sequences.
pub import "ids.rl"
pub import "frozen.rl"
import std.string_builder

pub enum TypeKind {
    case primitive; case struct_type; case enum_type; case function; case closure;
    case optional; case protocol; case existential; case type_variable; case error; case never;
}

pub enum PrimitiveType {
    case i8; case i16; case i32; case i64;
    case u8; case u16; case u32; case u64;
    case f32; case f64; case bool_type; case void_type; case raw_ptr;

    pub def spelling() -> String {
        switch self {
            case .i8: "i8"; case .i16: "i16"; case .i32: "i32"; case .i64: "i64";
            case .u8: "u8"; case .u16: "u16"; case .u32: "u32"; case .u64: "u64";
            case .f32: "f32"; case .f64: "f64"; case .bool_type: "Bool";
            case .void_type: "Void"; case .raw_ptr: "RawPtr";
        }
    }
    pub def integer_width() -> i32 {
        switch self {
            case .i8 | .u8: 8; case .i16 | .u16: 16;
            case .i32 | .u32: 32; case .i64 | .u64: 64; default: 0;
        }
    }
    pub def is_signed() -> Bool {
        switch self { case .i8 | .i16 | .i32 | .i64: true; default: false; }
    }
    pub def is_float() -> Bool {
        switch self { case .f32 | .f64: true; default: false; }
    }
}

pub struct TupleField { pub let name: String; pub let type_id: TypeId; }
pub struct StructTypeData {
    pub let symbol_id: SymbolId?;
    pub let type_args: FrozenVec<TypeId>;
    pub let anon_fields: FrozenVec<TupleField>? = nil;
}
pub struct EnumTypeData { pub let symbol_id: SymbolId; pub let type_args: FrozenVec<TypeId>; }
pub struct FunctionTypeData {
    pub let params: FrozenVec<TypeId>;
    pub let return_type: TypeId;
    pub let is_async: Bool = false;
}
pub struct ClosureTypeData {
    pub let params: FrozenVec<TypeId>;
    pub let return_type: TypeId;
    pub let captures: FrozenVec<TypeId>;
    pub let is_async: Bool = false;
}
pub struct FuncRequirement {
    pub let name: String;
    pub let params: FrozenVec<TypeId>;
    pub let return_type: TypeId;
    pub let is_async: Bool = false;
    pub let is_static: Bool = false;
    pub static def new(name: String, params: Vec<TypeId>, return_type: TypeId,
                       is_async: Bool = false, is_static: Bool = false) -> FuncRequirement {
        FuncRequirement { name, params: FrozenVec<TypeId>.new(params), return_type, is_async, is_static }
    }
}
pub struct PropRequirement {
    pub let name: String;
    pub let type_id: TypeId;
    pub let has_getter: Bool = true;
    pub let has_setter: Bool = false;
    pub static def new(name: String, type_id: TypeId, has_getter: Bool = true, has_setter: Bool = false) -> PropRequirement {
        PropRequirement { name, type_id, has_getter, has_setter }
    }
}
pub struct ProtocolTypeData {
    pub let symbol_id: SymbolId;
    pub let func_requirements: FrozenVec<FuncRequirement>;
    pub let prop_requirements: FrozenVec<PropRequirement>;
}
pub struct ExistentialTypeData { pub let protocol_id: TypeId; }
pub struct TypeVariableData {
    pub let name: String;
    pub let id: i32;
    pub let bounds: FrozenVec<TypeId>;
}

pub enum TypeData {
    case primitive(PrimitiveType);
    case struct_type(StructTypeData);
    case enum_type(EnumTypeData);
    case function(FunctionTypeData);
    case closure(ClosureTypeData);
    case optional(TypeId);
    case protocol(ProtocolTypeData);
    case existential(ExistentialTypeData);
    case type_variable(TypeVariableData);
    case error;
    case never;

    pub def kind() -> TypeKind {
        switch self {
            case .primitive(_): TypeKind.primitive();
            case .struct_type(_): TypeKind.struct_type();
            case .enum_type(_): TypeKind.enum_type();
            case .function(_): TypeKind.function();
            case .closure(_): TypeKind.closure();
            case .optional(_): TypeKind.optional();
            case .protocol(_): TypeKind.protocol();
            case .existential(_): TypeKind.existential();
            case .type_variable(_): TypeKind.type_variable();
            case .error: TypeKind.error(); case .never: TypeKind.never();
        }
    }

    // This is a structural identity encoding, never a display spelling.
    // Every atom is byte-length-prefixed; collection counts and optional tags
    // distinguish empty/missing payloads and prevent delimiter collisions.
    pub def key() -> String {
        let key = TypeKey.new();
        switch self {
            case .primitive(let primitive): key.atom("primitive"); key.atom(primitive.spelling());
            case .struct_type(let data):
                key.atom("struct");
                if let id = data.symbol_id { key.atom("named"); key.number(id.id); }
                else { key.atom("anonymous"); }
                key.types(data.type_args);
                if let fields = data.anon_fields {
                    key.atom("fields"); key.number(fields.len());
                    for field in fields { key.atom(field.name); key.number(field.type_id.id); }
                } else { key.atom("no-fields"); }
            case .enum_type(let data): key.atom("enum"); key.number(data.symbol_id.id); key.types(data.type_args);
            case .function(let data):
                key.atom("function"); key.types(data.params); key.number(data.return_type.id); key.flag(data.is_async);
            case .closure(let data):
                key.atom("closure"); key.types(data.params); key.number(data.return_type.id);
                key.types(data.captures); key.flag(data.is_async);
            case .optional(let inner): key.atom("optional"); key.number(inner.id);
            case .protocol(let data):
                key.atom("protocol"); key.number(data.symbol_id.id); key.number(data.func_requirements.len());
                for req in data.func_requirements {
                    key.atom(req.name); key.types(req.params); key.number(req.return_type.id);
                    key.flag(req.is_async); key.flag(req.is_static);
                }
                key.number(data.prop_requirements.len());
                for req in data.prop_requirements {
                    key.atom(req.name); key.number(req.type_id.id); key.flag(req.has_getter); key.flag(req.has_setter);
                }
            case .existential(let data): key.atom("existential"); key.number(data.protocol_id.id);
            case .type_variable(let data): key.atom("variable"); key.atom(data.name); key.number(data.id); key.types(data.bounds);
            case .error: key.atom("error"); case .never: key.atom("never");
        }
        key.text()
    }
}

struct TypeKey {
    let builder: StringBuilder;
    static def new() -> TypeKey { TypeKey { builder: StringBuilder.new() } }
    def atom(value: String) -> Void { self.builder.append(f"{value.len()}:{value}"); }
    def number(value: i32) -> Void { self.atom(value.to_string()); }
    def flag(value: Bool) -> Void { self.atom(value.to_string()); }
    def types(values: FrozenVec<TypeId>) -> Void {
        self.number(values.len());
        for value in values { self.number(value.id); }
    }
    def text() -> String { self.builder.to_string() }
}

pub struct TypeInfo { pub let id: TypeId; pub let kind: TypeKind; pub let data: TypeData; }
pub struct FieldDesc {
    pub var name: String;
    pub var offset: i32;
    pub var is_pointer: Bool;
    pub var inner_type_id: TypeId;
}
pub struct TypeDescriptorEntry {
    pub var type_id: TypeId;
    pub var payload_size: i32;
    pub var fields: Vec<FieldDesc>;
    pub def pointer_fields() -> Vec<FieldDesc> {
        let result = Vec<FieldDesc>.new();
        for field in self.fields { if field.is_pointer { result.push(field); } }
        result
    }
}
