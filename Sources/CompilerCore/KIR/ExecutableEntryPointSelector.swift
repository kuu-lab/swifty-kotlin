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
        if entryPointFQName == nil {
            // A file with top-level statements runs its synthesized script
            // body as the entry point (matching `kotlinc -script`), so prefer
            // it over a user-declared `fun main` in the same file.
            for file in ast.sortedFiles {
                for declID in file.topLevelDecls {
                    guard case let .funDecl(funDecl)? = ast.arena.decl(declID),
                          funDecl.isScriptEntryPoint,
                          let symbol = bindings.declSymbols[declID],
                          arena.function(for: symbol) != nil else { continue }
                    return symbol
                }
            }
        }
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
