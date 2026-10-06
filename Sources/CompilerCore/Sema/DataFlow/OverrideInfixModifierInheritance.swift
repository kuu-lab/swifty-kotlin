extension DataFlowSemaPhase {
    /// Infix notation remains available through overrides that omit the keyword.
    func inheritInfixModifierForOverrides(symbols: SymbolTable, types: TypeSystem) {
        var changed = true
        while changed {
            changed = false
            for symbol in symbols.allSymbols() where symbol.kind == .function
                && symbol.flags.contains(.overrideMember)
                && !symbol.flags.contains(.infixFunction)
                && !symbol.flags.contains(.importedLibrary)
            {
                if nearestOverriddenFunctionCandidates(of: symbol.id, symbols: symbols, types: types)
                    .contains(where: { symbols.symbol($0)?.flags.contains(.infixFunction) == true })
                {
                    symbols.insertFlags(.infixFunction, for: symbol.id)
                    changed = true
                }
            }
        }
    }
}
