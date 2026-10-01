// Lazy protocol witness tables and code-generation registry.
pub import "conformance.rl"

pub struct WitnessTable {
    pub let concrete_type: TypeId;
    pub let protocol_type: TypeId;
    pub let entries: Vec<WitnessEntry>;
    pub let global_name: String;
}
pub struct WitnessTableBuilder {
    pub let type_table: TypeTable;
    pub let symbol_table: SymbolTable;
    pub let conformance_checker: ConformanceChecker;
    let tables: Dict<String, WitnessTable>;
    var table_counter: i32;
    pub static def new(arena: AstArena, types: TypeTable, symbols: SymbolTable,
                       checker: ConformanceChecker? = nil) -> WitnessTableBuilder {
        WitnessTableBuilder { type_table: types, symbol_table: symbols,
            conformance_checker: checker ?? ConformanceChecker.new(arena, types, symbols),
            tables: Dict<String, WitnessTable>.with_capacity(16, 1), table_counter: 0 }
    }
    pub def get_or_create_table(concrete: TypeId, protocol: TypeId) -> WitnessTable? {
        let key = f"{concrete.id}:{protocol.id}";
        if let table = self.tables[key] { return table; }
        let result = self.conformance_checker.check_conformance(concrete, protocol);
        if !result.conforms { return nil; }
        let name = f"__witness_{self.type_name(concrete)}_{self.type_name(protocol)}_{self.table_counter}";
        self.table_counter += 1;
        let table = WitnessTable { concrete_type: concrete, protocol_type: protocol,
            entries: result.witnesses, global_name: name };
        self.tables[key] = table;
        table
    }
    def type_name(type: TypeId) -> String {
        var symbol_id: SymbolId? = nil;
        if let info = self.type_table.get_type(type) {
            switch info.data {
                case .struct_type(let data): symbol_id = data.symbol_id;
                case .enum_type(let data): symbol_id = data.symbol_id;
                case .protocol(let data): symbol_id = data.symbol_id;
                default: {}
            }
        }
        if let id = symbol_id { if let symbol = self.symbol_table.get_symbol(id) { return symbol.name; } }
        f"type{type.id}"
    }
    pub def get_all_tables() -> Vec<WitnessTable> { self.tables.values() }
    pub def get_method_index(protocol: TypeId, name: String) -> i32? {
        guard let info = self.type_table.get_type(protocol) else { return nil; }
        switch info.data {
            case .protocol(let data):
                var index = 0;
                for requirement in data.func_requirements { if requirement.name.equals(name) { return index; } index += 1; }
                for requirement in data.prop_requirements { if requirement.name.equals(name) { return index; } index += 1; }
            default: {}
        }
        nil
    }
}
pub struct WitnessTableRegistry {
    pub let tables: Vec<WitnessTable>;
    pub static def new() -> WitnessTableRegistry { WitnessTableRegistry { tables: Vec<WitnessTable>.new() } }
    pub def add_table(table: WitnessTable) -> Void {
        if let previous = self.get_table(table.concrete_type, table.protocol_type) { return; }
        self.tables.push(table);
    }
    pub def get_table(concrete: TypeId, protocol: TypeId) -> WitnessTable? {
        for table in self.tables { if table.concrete_type == concrete && table.protocol_type == protocol { return table; } }
        nil
    }
}
