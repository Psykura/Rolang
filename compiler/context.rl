// Shared state and ordered pass execution.
pub import "symbols.rl"
pub import "types.rl"
pub import "diagnostics.rl"
import std.io

pub struct CompilerContext {
    pub let symbol_table: SymbolTable;
    pub let type_table: TypeTable;
    pub let diagnostics: DiagnosticCollector;
    pub let node_symbols: Dict<i32, SymbolId>;
    pub let imported_symbols: Dict<String, SymbolId>;

    pub static def new(symbol_table: SymbolTable, type_table: TypeTable,
                       diagnostics: DiagnosticCollector) -> CompilerContext {
        CompilerContext {
            symbol_table, type_table, diagnostics,
            node_symbols: Dict<i32, SymbolId>.with_capacity(16, 0),
            imported_symbols: Dict<String, SymbolId>.with_capacity(16, 1)
        }
    }
    pub def has_errors() -> Bool { self.diagnostics.has_errors() }
    pub def symbol_for_node(node: NodeId) -> SymbolId? { self.node_symbols[node.id] }
    pub def bind_node(node: NodeId, symbol: SymbolId) -> Void {
        self.node_symbols[node.id] = symbol;
    }
}

pub struct PassRunner {
    pub let context: CompilerContext;
    pub let verbose: Bool;
    let passes: Vec<String>;

    pub static def new(context: CompilerContext, verbose: Bool = false) -> PassRunner {
        PassRunner { context, verbose, passes: Vec<String>.new() }
    }
    pub def run<T>(name: String, pass_fn: () -> T) -> T {
        if self.verbose { println(f"{name}..."); }
        self.passes.push(name);
        pass_fn()
    }
    pub def executed_passes() -> Vec<String> {
        let result = Vec<String>.new();
        for name in self.passes { result.push(name); }
        result
    }
}
