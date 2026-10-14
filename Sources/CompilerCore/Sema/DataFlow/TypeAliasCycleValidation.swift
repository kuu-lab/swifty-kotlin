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

/// A typealias whose right-hand side mentions an alias declared *later* in the
/// same file is resolved before that alias has an underlying type, so the
/// nested reference survives unexpanded (`typealias Mw = (Name) -> Name;
/// typealias Name = String` leaves `Name` inside the function type). Expand
/// those references once every alias header is known so both declaration
/// orders yield the same underlying type.
extension DataFlowSemaPhase {
    func normalizeNestedTypeAliasUnderlyingTypes(symbols: SymbolTable, types: TypeSystem) {
        for aliasID in symbols.symbols(ofKind: .typeAlias) {
            guard let underlying = symbols.typeAliasUnderlyingType(for: aliasID) else { continue }
            let normalized = expandNestedTypeAliases(
                in: underlying, inProgress: [aliasID], depth: 0, symbols: symbols, types: types
            )
            if normalized != underlying {
                symbols.setTypeAliasUnderlyingType(normalized, for: aliasID)
            }
        }
    }

    func expandNestedTypeAliases(
        in typeID: TypeID,
        inProgress: Set<SymbolID>,
        depth: Int,
        symbols: SymbolTable,
        types: TypeSystem
    ) -> TypeID {
        guard depth < TypeCheckHelpers.maxAliasExpansionDepth else { return typeID }
        func expand(_ type: TypeID) -> TypeID {
            expandNestedTypeAliases(
                in: type, inProgress: inProgress, depth: depth + 1, symbols: symbols, types: types
            )
        }
        func expandArg(_ arg: TypeArg) -> TypeArg {
            switch arg {
            case let .invariant(inner): .invariant(expand(inner))
            case let .out(inner): .out(expand(inner))
            case let .in(inner): .in(expand(inner))
            case .star: .star
            }
        }
        switch types.kind(of: typeID) {
        case let .classType(classType):
            let newArgs = classType.args.map(expandArg)
            if symbols.symbol(classType.classSymbol)?.kind == .typeAlias {
                // Cycles are reported by `validateTypeAliasCycles`; leave them as is.
                guard !inProgress.contains(classType.classSymbol),
                      let resolved = resolveTypeAliasUnderlying(
                          classType.classSymbol, symbols: symbols, types: types,
                          typeArgs: newArgs, visited: []
                      )
                else { return typeID }
                var nested = inProgress
                nested.insert(classType.classSymbol)
                let expanded = expandNestedTypeAliases(
                    in: resolved, inProgress: nested, depth: depth + 1, symbols: symbols, types: types
                )
                return classType.nullability == .nullable ? applyNullability(expanded, types: types) : expanded
            }
            if newArgs == classType.args { return typeID }
            return types.make(.classType(ClassType(
                classSymbol: classType.classSymbol, args: newArgs, nullability: classType.nullability
            )))
        case let .functionType(functionType):
            let contextReceivers = functionType.contextReceivers.map(expand)
            let receiver = functionType.receiver.map(expand)
            let params = functionType.params.map(expand)
            let returnType = expand(functionType.returnType)
            if contextReceivers == functionType.contextReceivers, receiver == functionType.receiver,
               params == functionType.params, returnType == functionType.returnType
            {
                return typeID
            }
            return types.make(.functionType(FunctionType(
                contextReceivers: contextReceivers, receiver: receiver, params: params,
                returnType: returnType, isSuspend: functionType.isSuspend,
                isCallableReference: functionType.isCallableReference, nullability: functionType.nullability
            )))
        case let .intersection(parts):
            let newParts = parts.map(expand)
            return newParts == parts ? typeID : types.make(.intersection(newParts))
        default:
            return typeID
        }
    }
}
