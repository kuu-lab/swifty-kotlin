/// Synthetic fallback declarations for kotlin.require, kotlin.check, assert, and error.
/// Source stdlib declarations own these symbols when imported; this fallback only
/// keeps no-stdlib-search Sema paths contract-aware.
extension DataFlowSemaPhase {
    func registerSyntheticPreconditionStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        bundledIndex: BundledDeclarationIndex = .empty,
        skipStats: SyntheticStubSkipStatsCollector? = nil
    ) {
        let kotlinPkg: [InternedString] = [interner.intern("kotlin")]
        _ = ensureSyntheticPackage(fqName: kotlinPkg, symbols: symbols)
        let packageSymbol = symbols.lookup(fqName: kotlinPkg) ?? .invalid
        let lazyMessageType = types.make(.functionType(FunctionType(
            params: [],
            returnType: types.anyType,
            isSuspend: false,
            nullability: .nonNull
        )))

        registerSyntheticPreconditionTopLevelFunction(
            named: "require",
            packageFQName: kotlinPkg,
            packageSymbol: packageSymbol,
            parameters: [(name: "condition", type: types.booleanType)],
            returnType: types.unitType,
            externalLinkName: nil,
            symbols: symbols,
            interner: interner,
            bundledIndex: bundledIndex,
            skipStats: skipStats,
            contractNonNullParameterIndex: 0
        )
        registerSyntheticPreconditionTopLevelFunction(
            named: "require",
            packageFQName: kotlinPkg,
            packageSymbol: packageSymbol,
            parameters: [
                (name: "condition", type: types.booleanType),
                (name: "lazyMessage", type: lazyMessageType),
            ],
            returnType: types.unitType,
            externalLinkName: nil,
            symbols: symbols,
            interner: interner,
            bundledIndex: bundledIndex,
            skipStats: skipStats,
            contractNonNullParameterIndex: 0
        )
        registerSyntheticPreconditionTopLevelFunction(
            named: "check",
            packageFQName: kotlinPkg,
            packageSymbol: packageSymbol,
            parameters: [(name: "condition", type: types.booleanType)],
            returnType: types.unitType,
            externalLinkName: nil,
            symbols: symbols,
            interner: interner,
            bundledIndex: bundledIndex,
            skipStats: skipStats,
            contractNonNullParameterIndex: 0
        )
        registerSyntheticPreconditionTopLevelFunction(
            named: "check",
            packageFQName: kotlinPkg,
            packageSymbol: packageSymbol,
            parameters: [
                (name: "condition", type: types.booleanType),
                (name: "lazyMessage", type: lazyMessageType),
            ],
            returnType: types.unitType,
            externalLinkName: nil,
            symbols: symbols,
            interner: interner,
            bundledIndex: bundledIndex,
            skipStats: skipStats,
            contractNonNullParameterIndex: 0
        )
        registerSyntheticPreconditionTopLevelFunction(
            named: "assert",
            packageFQName: kotlinPkg,
            packageSymbol: packageSymbol,
            parameters: [(name: "value", type: types.booleanType)],
            returnType: types.unitType,
            externalLinkName: nil,
            symbols: symbols,
            interner: interner,
            bundledIndex: bundledIndex,
            skipStats: skipStats,
            contractNonNullParameterIndex: 0
        )
        registerSyntheticPreconditionTopLevelFunction(
            named: "assert",
            packageFQName: kotlinPkg,
            packageSymbol: packageSymbol,
            parameters: [
                (name: "value", type: types.booleanType),
                (name: "lazyMessage", type: lazyMessageType),
            ],
            returnType: types.unitType,
            externalLinkName: nil,
            symbols: symbols,
            interner: interner,
            bundledIndex: bundledIndex,
            skipStats: skipStats,
            contractNonNullParameterIndex: 0
        )
        registerSyntheticPreconditionTopLevelFunction(
            named: "error",
            packageFQName: kotlinPkg,
            packageSymbol: packageSymbol,
            parameters: [(name: "message", type: types.anyType)],
            returnType: types.nothingType,
            externalLinkName: nil,
            symbols: symbols,
            interner: interner,
            bundledIndex: bundledIndex,
            skipStats: skipStats
        )
    }

    private func registerSyntheticPreconditionTopLevelFunction(
        named name: String,
        packageFQName: [InternedString],
        packageSymbol: SymbolID,
        parameters: [(name: String, type: TypeID)],
        returnType: TypeID,
        externalLinkName: String?,
        symbols: SymbolTable,
        interner: StringInterner,
        bundledIndex: BundledDeclarationIndex,
        skipStats: SyntheticStubSkipStatsCollector?,
        contractNonNullParameterIndex: Int? = nil
    ) {
        let functionName = interner.intern(name)
        let functionFQName = packageFQName + [functionName]

        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
            guard let existingSignature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return existingSignature.receiverType == nil
                && existingSignature.parameterTypes == parameters.map(\.type)
                && existingSignature.returnType == returnType
        }) {
            let existingFlags = symbols.symbol(existing)?.flags ?? []
            if let externalLinkName, existingFlags.contains(.synthetic) && !existingFlags.contains(.importedLibrary) {
                symbols.setExternalLinkName(externalLinkName, for: existing)
            }
            setPreconditionContractEffect(
                on: existing,
                parameterIndex: contractNonNullParameterIndex,
                symbols: symbols
            )
            return
        }

        if shouldSkipSyntheticStub(
            bundledIndex: bundledIndex,
            ownerFQName: packageFQName,
            name: functionName,
            arity: parameters.count
        ) {
            skipStats?.recordSkip(
                ownerFQName: packageFQName,
                name: functionName,
                arity: parameters.count,
                interner: interner
            )
            return
        }

        if hasSourceOrImportedLibrarySymbol(fqName: functionFQName, kind: .function, symbols: symbols) {
            return
        }

        guard let externalLinkName else { return }

        let functionSymbol = symbols.define(
            kind: .function,
            name: functionName,
            fqName: functionFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        if packageSymbol != .invalid {
            symbols.setParentSymbol(packageSymbol, for: functionSymbol)
        }
        symbols.setExternalLinkName(externalLinkName, for: functionSymbol)

        let valueParameterSymbols = parameters.map { parameter in
            let parameterName = interner.intern(parameter.name)
            let parameterSymbol = symbols.define(
                kind: .valueParameter,
                name: parameterName,
                fqName: functionFQName + [parameterName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(functionSymbol, for: parameterSymbol)
            return parameterSymbol
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: parameters.map(\.type),
                returnType: returnType,
                isSuspend: false,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: valueParameterSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count)
            ),
            for: functionSymbol
        )
        setPreconditionContractEffect(
            on: functionSymbol,
            parameterIndex: contractNonNullParameterIndex,
            symbols: symbols
        )
    }

    /// Source-backed `kotlin.require`/`kotlin.check` are collected after synthetic
    /// registration runs, so their `ContractNonNullEffect` is patched once the
    /// bundled declarations are in the symbol table.
    func patchSourceBackedPreconditionContractEffects(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinPkg: [InternedString] = [interner.intern("kotlin")]
        let lazyMessageType = types.make(.functionType(FunctionType(
            params: [],
            returnType: types.anyType,
            isSuspend: false,
            nullability: .nonNull
        )))

        let preconditionFunctions: [(name: String, parameterTypes: [TypeID])] = [
            ("require", [types.booleanType]),
            ("require", [types.booleanType, lazyMessageType]),
            ("check", [types.booleanType]),
            ("check", [types.booleanType, lazyMessageType]),
            ("assert", [types.booleanType]),
            ("assert", [types.booleanType, lazyMessageType]),
        ]

        for entry in preconditionFunctions {
            let functionName = interner.intern(entry.name)
            let functionFQName = kotlinPkg + [functionName]
            guard let symbol = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
                guard let symbol = symbols.symbol(symbolID),
                      symbol.kind == .function,
                      !symbol.flags.contains(.synthetic),
                      let signature = symbols.functionSignature(for: symbolID)
                else {
                    return false
                }
                return signature.receiverType == nil
                    && signature.parameterTypes == entry.parameterTypes
                    && signature.returnType == types.unitType
            }) else {
                continue
            }
            setPreconditionContractEffect(
                on: symbol,
                parameterIndex: 0,
                symbols: symbols
            )
        }
    }

    private func setPreconditionContractEffect(
        on functionSymbol: SymbolID,
        parameterIndex: Int?,
        symbols: SymbolTable
    ) {
        guard let parameterIndex,
              let signature = symbols.functionSignature(for: functionSymbol),
              parameterIndex < signature.valueParameterSymbols.count
        else {
            return
        }
        symbols.setContractNonNullEffect(
            ContractNonNullEffect(
                parameterSymbol: signature.valueParameterSymbols[parameterIndex],
                appliesOnAnyReturn: true
            ),
            for: functionSymbol
        )
    }
}
