
extension TypeCheckHelpers {
    /// Maximum depth for recursive typealias expansion to prevent infinite loops.
    static let maxAliasExpansionDepth = 32

    /// Resolve an expect class or its actual typealias to the nominal type used
    /// by platform member lookup. The source-facing expression keeps its
    /// declared expect type; only the lookup view follows the actual link.
    func actualImplementationType(of typeID: TypeID, sema: SemaModule) -> TypeID? {
        guard case let .classType(classType) = sema.types.kind(of: typeID),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return nil
        }

        let implementationID: SymbolID?
        if symbol.kind == .typeAlias, symbol.flags.contains(.actualDeclaration) {
            implementationID = symbol.id
        } else if symbol.flags.contains(.expectDeclaration) {
            implementationID = sema.symbols.actualSymbol(for: symbol.id)
        } else {
            implementationID = nil
        }
        guard let implementationID,
              let implementation = sema.symbols.symbol(implementationID)
        else {
            return nil
        }

        let implementationType: TypeID?
        if implementation.kind == .typeAlias {
            implementationType = expandTypeAlias(
                implementationID,
                typeArgs: classType.args,
                sema: sema,
                visited: [],
                depth: 0
            )
        } else if implementation.kind == .class {
            implementationType = sema.types.make(.classType(ClassType(
                classSymbol: implementationID,
                args: classType.args,
                nullability: classType.nullability
            )))
        } else {
            implementationType = nil
        }
        guard let implementationType else { return nil }
        return sema.types.withNullability(classType.nullability, for: implementationType)
    }

    func expandTypeAlias(
        _ symbolID: SymbolID,
        typeArgs: [TypeArg],
        sema: SemaModule,
        visited: Set<SymbolID>,
        depth: Int,
        diagnostics: DiagnosticEngine? = nil,
        projectionRange: SourceRange? = nil
    ) -> TypeID? {
        guard !visited.contains(symbolID) else {
            diagnostics?.error(
                "KSWIFTK-SEMA-ALIAS-CYCLE",
                "Cyclic typealias definition detected.",
                range: sema.symbols.symbol(symbolID)?.declSite
            )
            return nil
        }
        guard depth < TypeCheckHelpers.maxAliasExpansionDepth else {
            diagnostics?.error(
                "KSWIFTK-SEMA-ALIAS-DEPTH",
                "Typealias expansion exceeded maximum depth of \(TypeCheckHelpers.maxAliasExpansionDepth).",
                range: sema.symbols.symbol(symbolID)?.declSite
            )
            return nil
        }
        guard let underlying = sema.symbols.typeAliasUnderlyingType(for: symbolID) else {
            return nil
        }
        let expanded = substituteTypeAliasParamsForTypeCheck(
            underlying,
            aliasSymbol: symbolID,
            typeArgs: typeArgs,
            sema: sema,
            diagnostics: diagnostics
        )
        TypeProjectionValidator(symbols: sema.symbols, types: sema.types,
                                interner: sema.interner, diagnostics: diagnostics,
                                range: projectionRange ?? sema.symbols.symbol(symbolID)?.declSite)
            .validate(arguments: typeArgs, of: symbolID)
        if case let .classType(classType) = sema.types.kind(of: expanded),
           let targetSymbol = sema.symbols.symbol(classType.classSymbol),
           targetSymbol.kind == .typeAlias
        {
            var newVisited = visited
            newVisited.insert(symbolID)
            let chainArgs = classType.args
            if let resolved = expandTypeAlias(
                classType.classSymbol,
                typeArgs: chainArgs,
                sema: sema,
                visited: newVisited,
                depth: depth + 1,
                diagnostics: diagnostics,
                projectionRange: projectionRange
            ) {
                if classType.nullability == .nullable {
                    return applyNullabilityForTypeCheck(resolved, types: sema.types)
                }
                return resolved
            }
            return nil
        }
        if case let .classType(classType) = sema.types.kind(of: expanded),
           let expectSymbol = sema.symbols.symbol(classType.classSymbol),
           expectSymbol.flags.contains(.expectDeclaration),
           let actualSymbolID = sema.symbols.actualSymbol(for: expectSymbol.id),
           let actualSymbol = sema.symbols.symbol(actualSymbolID)
        {
            if actualSymbol.kind == .class {
                return sema.types.make(.classType(ClassType(
                    classSymbol: actualSymbolID,
                    args: classType.args,
                    nullability: classType.nullability
                )))
            }
            if actualSymbol.kind == .typeAlias,
               let resolved = expandTypeAlias(
                   actualSymbolID,
                   typeArgs: classType.args,
                   sema: sema,
                   visited: visited.union([symbolID]),
                   depth: depth + 1,
                   diagnostics: diagnostics
               )
            {
                return resolved
            }
        }
        return expanded
    }

    func substituteTypeAliasParamsForTypeCheck(
        _ typeID: TypeID,
        aliasSymbol: SymbolID,
        typeArgs: [TypeArg],
        sema: SemaModule,
        diagnostics: DiagnosticEngine? = nil
    ) -> TypeID {
        let typeParamSymbols = sema.symbols.typeAliasTypeParameters(for: aliasSymbol)
        if typeParamSymbols.isEmpty {
            return typeID
        }
        if typeArgs.count != typeParamSymbols.count {
            diagnostics?.error(
                "KSWIFTK-SEMA-0062",
                "Type argument count mismatch: expected \(typeParamSymbols.count) but got \(typeArgs.count).",
                range: nil
            )
        }
        var argSubstitution: [SymbolID: TypeArg] = [:]
        for (index, paramSymbol) in typeParamSymbols.enumerated() {
            guard index < typeArgs.count else { break }
            argSubstitution[paramSymbol] = typeArgs[index]
        }
        guard !argSubstitution.isEmpty else {
            return typeID
        }
        return applyAliasSubstitution(typeID, argSubstitution: argSubstitution, sema: sema)
    }

    func applyAliasSubstitution(
        _ typeID: TypeID,
        argSubstitution: [SymbolID: TypeArg],
        sema: SemaModule
    ) -> TypeID {
        let types = sema.types
        switch types.kind(of: typeID) {
        case let .typeParam(typeParam):
            return applyAliasToTypeParam(typeParam, typeID: typeID, argSubstitution: argSubstitution, types: types)
        case let .classType(clsType):
            let newArgs = clsType.args.map { arg -> TypeArg in
                substituteAliasArg(arg, argSubstitution: argSubstitution, sema: sema)
            }
            let newEnclosingTypeArgs = clsType.enclosingTypeArgs.map { arg in
                substituteAliasArg(arg, argSubstitution: argSubstitution, sema: sema)
            }
            if newArgs == clsType.args && newEnclosingTypeArgs == clsType.enclosingTypeArgs { return typeID }
            return types.make(.classType(ClassType(
                classSymbol: clsType.classSymbol,
                args: newArgs,
                enclosingTypeArgs: newEnclosingTypeArgs,
                nullability: clsType.nullability
            )))
        case let .functionType(fnType):
            let newContextReceivers = fnType.contextReceivers.map {
                applyAliasSubstitution($0, argSubstitution: argSubstitution, sema: sema)
            }
            let newReceiver = fnType.receiver.map {
                applyAliasSubstitution($0, argSubstitution: argSubstitution, sema: sema)
            }
            let newParams = fnType.params.map {
                applyAliasSubstitution($0, argSubstitution: argSubstitution, sema: sema)
            }
            let newReturn = applyAliasSubstitution(
                fnType.returnType, argSubstitution: argSubstitution, sema: sema
            )
            if newContextReceivers == fnType.contextReceivers,
               newReceiver == fnType.receiver,
               newParams == fnType.params,
               newReturn == fnType.returnType
            {
                return typeID
            }
            return types.make(.functionType(FunctionType(
                contextReceivers: newContextReceivers,
                receiver: newReceiver, params: newParams, returnType: newReturn,
                isSuspend: fnType.isSuspend, isCallableReference: fnType.isCallableReference,
                nullability: fnType.nullability
            )))
        case let .intersection(parts):
            let newParts = parts.map {
                applyAliasSubstitution($0, argSubstitution: argSubstitution, sema: sema)
            }
            if newParts == parts { return typeID }
            return types.make(.intersection(newParts))
        default:
            return typeID
        }
    }

    private func applyAliasToTypeParam(
        _ typeParam: TypeParamType,
        typeID: TypeID,
        argSubstitution: [SymbolID: TypeArg],
        types: TypeSystem
    ) -> TypeID {
        guard let replacement = argSubstitution[typeParam.symbol] else { return typeID }
        let replacementType: TypeID = switch replacement {
        case let .invariant(inner), let .out(inner), let .in(inner): inner
        case .star: types.nullableAnyType
        }
        if typeParam.nullability == .nullable {
            return applyNullabilityForTypeCheck(replacementType, types: types)
        }
        return replacementType
    }
}
