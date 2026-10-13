/// Shared file-level entry selection for initializer injection and Link.
/// Keeps the existing first-match order and exact-FQName behavior.
public enum ExecutableEntryPointSelector {
    public static func firstFileLevelSymbol(
        ast: ASTModule,
        bindings: BindingTable,
        arena: KIRArena,
        interner: StringInterner,
        symbols: SymbolTable?,
        entryPointFQName: String?
    ) -> SymbolID? {
        let mainName = interner.intern("main")
        for file in ast.sortedFiles {
            for declID in file.topLevelDecls {
                guard case .funDecl? = ast.arena.decl(declID),
                      let symbol = bindings.declSymbols[declID],
                      let function = arena.function(for: symbol) else { continue }
                let matches: Bool
                if let entryPointFQName {
                    matches = symbols?.symbol(symbol)?.fqName.map(interner.resolve).joined(separator: ".") == entryPointFQName
                } else {
                    matches = function.name == mainName || interner.resolve(function.name) == "main"
                }
                if matches { return symbol }
            }
        }
        return nil
    }
}
