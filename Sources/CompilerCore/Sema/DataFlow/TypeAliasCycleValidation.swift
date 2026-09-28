/// Declaration-site check for recursive type aliases.
///
/// `Helpers+TypeAliasExpansion.expandTypeAlias` already detects cycles, but only when an
/// alias is *expanded* at a use site; a cyclic alias that is never referenced compiles
/// silently. Kotlin rejects `typealias A = B; typealias B = A` at the declaration
/// regardless of usage, so each alias's underlying type is walked here once. Every alias
/// participating in a cycle reports its own diagnostic, matching kotlinc, which flags
/// every declaration whose expansion recurs.
extension DataFlowSemaPhase {
    func validateTypeAliasCycles(
        symbols: SymbolTable,
        types: TypeSystem,
        diagnostics: DiagnosticEngine
    ) {
        for aliasID in symbols.symbols(ofKind: .typeAlias) {
            guard let underlying = symbols.typeAliasUnderlyingType(for: aliasID) else {
                continue
            }
            if typeAliasExpansionCycles(
                from: underlying,
                visited: [aliasID],
                depth: 0,
                symbols: symbols,
                types: types
            ) {
                diagnostics.error(
                    "KSWIFTK-SEMA-ALIAS-CYCLE",
                    "Cyclic typealias definition detected.",
                    range: symbols.symbol(aliasID)?.declSite
                )
            }
        }
    }

    private func typeAliasExpansionCycles(
        from typeID: TypeID,
        visited: Set<SymbolID>,
        depth: Int,
        symbols: SymbolTable,
        types: TypeSystem
    ) -> Bool {
        guard depth < TypeCheckHelpers.maxAliasExpansionDepth else {
            return false
        }
        switch types.kind(of: typeID) {
        case let .classType(classType):
            if symbols.symbol(classType.classSymbol)?.kind == .typeAlias {
                if visited.contains(classType.classSymbol) {
                    return true
                }
                var nestedVisited = visited
                nestedVisited.insert(classType.classSymbol)
                if let underlying = symbols.typeAliasUnderlyingType(for: classType.classSymbol),
                   typeAliasExpansionCycles(
                       from: underlying,
                       visited: nestedVisited,
                       depth: depth + 1,
                       symbols: symbols,
                       types: types
                   )
                {
                    return true
                }
            }
            return classType.args.contains { arg in
                typeAliasArgCycles(arg, visited: visited, depth: depth + 1, symbols: symbols, types: types)
            }
        case let .functionType(functionType):
            let parts = functionType.contextReceivers
                + (functionType.receiver.map { [$0] } ?? [])
                + functionType.params
                + [functionType.returnType]
            return parts.contains { part in
                typeAliasExpansionCycles(
                    from: part, visited: visited, depth: depth + 1, symbols: symbols, types: types
                )
            }
        case let .intersection(parts):
            return parts.contains { part in
                typeAliasExpansionCycles(
                    from: part, visited: visited, depth: depth + 1, symbols: symbols, types: types
                )
            }
        default:
            return false
        }
    }

    private func typeAliasArgCycles(
        _ arg: TypeArg,
        visited: Set<SymbolID>,
        depth: Int,
        symbols: SymbolTable,
        types: TypeSystem
    ) -> Bool {
        switch arg {
        case let .invariant(inner), let .out(inner), let .in(inner):
            return typeAliasExpansionCycles(
                from: inner, visited: visited, depth: depth, symbols: symbols, types: types
            )
        case .star:
            return false
        }
    }
}
