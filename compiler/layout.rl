// Storage and payload layout for the 64-bit host ABI.
pub import "type_resolver.rl"

pub def align_up(value: i64, alignment: i64) -> i64 {
    if alignment <= 1 { return value; }
    ((value + alignment - 1) / alignment) * alignment
}
pub struct FieldLayout {
    pub let name: String; pub let type_id: TypeId; pub let index: i32;
}
pub struct StructLayout {
    pub let symbol_id: SymbolId;
    pub let fields: Vec<FieldLayout>;
    pub let size: i64;
    pub let alignment: i64;
}
pub struct EnumCaseLayout {
    pub let name: String;
    pub let tag: i32;
    pub let payload_size: i64;
    pub let payload_layout: Vec<(i64, TypeId)>;
}
pub struct EnumLayout {
    pub let symbol_id: SymbolId;
    pub let cases: Vec<EnumCaseLayout>;
    pub let tag_size: i64;
    pub let max_payload_size: i64;
    pub let size: i64;
    pub let alignment: i64;
}
pub struct LayoutService {
    pub let arena: AstArena;
    pub let type_table: TypeTable;
    pub let symbol_table: SymbolTable;
    let type_resolver: TypeResolver;
    let size_cache: Dict<i32, i64>;
    let struct_cache: Dict<i32, StructLayout>;
    let enum_cache: Dict<i32, EnumLayout>;
    pub static def new(arena: AstArena, type_table: TypeTable, symbol_table: SymbolTable,
                       type_resolver: TypeResolver? = nil) -> LayoutService {
        LayoutService {
            arena, type_table, symbol_table,
            type_resolver: type_resolver ?? TypeResolver.new(arena, type_table, symbol_table, nil, nil, nil, true),
            size_cache: Dict<i32, i64>.with_capacity(16, 0),
            struct_cache: Dict<i32, StructLayout>.with_capacity(16, 0),
            enum_cache: Dict<i32, EnumLayout>.with_capacity(16, 0)
        }
    }
    pub def size_of(type_id: TypeId) -> i64 {
        if let cached = self.size_cache[type_id.id] { return cached; }
        var result: i64 = 8;
        if let info = self.type_table.get_type(type_id) {
            switch info.data {
                case .primitive(let value):
                    switch value {
                        case .i8, .u8, .bool_type: result = 1;
                        case .i16, .u16: result = 2;
                        case .i32, .u32, .f32: result = 4;
                        case .void_type: result = 0;
                        default: result = 8;
                    }
                case .optional(let inner):
                    var pointer = false;
                    if let payload = self.type_table.get_type(inner) {
                        switch payload.kind {
                            case .struct_type, .enum_type, .closure, .existential, .function: pointer = true;
                            default: {}
                        }
                    }
                    if !pointer {
                        let size = self.size_of(inner);
                        let alignment = self.align_of(inner);
                        result = align_up(align_up(1, alignment) + size, alignment);
                    }
                default: {}
            }
        }
        self.size_cache[type_id.id] = result;
        result
    }
    pub def align_of(type_id: TypeId) -> i64 {
        let size = self.size_of(type_id);
        if size <= 1 { return 1; }
        if size <= 2 { return 2; }
        if size <= 4 { return 4; }
        8
    }
    pub def payload_size_of(type_id: TypeId) -> i64 {
        guard let info = self.type_table.get_type(type_id) else { return 8; }
        switch info.data {
            case .struct_type(let data):
                if let symbol = data.symbol_id {
                    if let layout = self.get_struct_layout(symbol) { return layout.size; }
                    return 8;
                }
                var size: i64 = 0;
                if let fields = data.anon_fields { for field in fields { size += self.size_of(field.type_id); } }
                return size;
            case .enum_type(let data):
                if let layout = self.get_enum_layout(data.symbol_id) { return layout.size; }
                return 8;
            default: return self.size_of(type_id);
        }
    }
    pub def get_struct_layout(symbol_id: SymbolId) -> StructLayout? {
        if let cached = self.struct_cache[symbol_id.id] { return cached; }
        guard let symbol = self.symbol_table.get_symbol(symbol_id) else { return nil; }
        guard let id = symbol.decl_node else { return nil; }
        guard let node = self.arena.get(id) else { return nil; }
        switch node.form {
            case .struct_decl(let data):
                let fields = Vec<FieldLayout>.new();
                var size: i64 = 0;
                for member in data.members {
                    guard let member_node = self.arena.get(member) else { continue; }
                    switch member_node.form {
                        case .property_decl(let property):
                            if let annotation = property.type_annotation {
                                let type_id = self.type_resolver.resolve(annotation);
                                fields.push(FieldLayout { name: property.name, type_id, index: fields.len() });
                                size += self.size_of(type_id);
                            }
                        default: {}
                    }
                }
                if size < 1 { size = 1; }
                let layout = StructLayout {
                    symbol_id, fields, size, alignment: self.align_of(self.type_table.make_struct(symbol_id))
                };
                self.struct_cache[symbol_id.id] = layout;
                return layout;
            default: {}
        }
        nil
    }
    pub def get_enum_layout(symbol_id: SymbolId) -> EnumLayout? {
        if let cached = self.enum_cache[symbol_id.id] { return cached; }
        guard let symbol = self.symbol_table.get_symbol(symbol_id) else { return nil; }
        guard let id = symbol.decl_node else { return nil; }
        guard let node = self.arena.get(id) else { return nil; }
        switch node.form {
            case .enum_decl(let data):
                let cases = Vec<EnumCaseLayout>.new();
                var max_payload: i64 = 0;
                for member in data.members {
                    guard let member_node = self.arena.get(member) else { continue; }
                    switch member_node.form {
                        case .enum_case_decl(let group):
                            for case_id in group.cases {
                                guard let case_node = self.arena.get(case_id) else { continue; }
                                switch case_node.form {
                                    case .enum_case_def(let item):
                                        var size: i64 = 0;
                                        let payload = Vec<(i64, TypeId)>.new();
                                        for pair in item.payload {
                                            let type_id = self.type_resolver.resolve(pair.1);
                                            payload.push((size, type_id)); size += self.size_of(type_id);
                                        }
                                        cases.push(EnumCaseLayout { name: item.name, tag: cases.len(), payload_size: size, payload_layout: payload });
                                        if size > max_payload { max_payload = size; }
                                    default: {}
                                }
                            }
                        default: {}
                    }
                }
                var tag_size: i64 = 1;
                if cases.len() > 65536 { tag_size = 4; }
                else if cases.len() > 256 { tag_size = 2; }
                var alignment = tag_size;
                if max_payload > 0 { alignment = 8; }
                let layout = EnumLayout {
                    symbol_id, cases, tag_size, max_payload_size: max_payload,
                    size: tag_size + max_payload, alignment
                };
                self.enum_cache[symbol_id.id] = layout;
                return layout;
            default: {}
        }
        nil
    }
}
