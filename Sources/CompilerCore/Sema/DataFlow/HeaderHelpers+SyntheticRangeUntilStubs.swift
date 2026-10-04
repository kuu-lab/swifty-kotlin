
extension DataFlowSemaPhase {
    func registerSyntheticRangeUntilStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinName = interner.intern("kotlin")
        let rangesName = interner.intern("ranges")
        let kotlinFQName: [InternedString] = [kotlinName]
        if symbols.lookup(fqName: kotlinFQName) == nil {
            _ = symbols.define(
                kind: .package,
                name: kotlinName,
                fqName: kotlinFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }

        let rangesFQName: [InternedString] = [kotlinName, rangesName]
        let rangesPackageSymbol: SymbolID
        if let existing = symbols.lookup(fqName: rangesFQName) {
            rangesPackageSymbol = existing
        } else {
            rangesPackageSymbol = symbols.define(
                kind: .package,
                name: rangesName,
                fqName: rangesFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            if let kotlinSymbol = symbols.lookup(fqName: kotlinFQName) {
                symbols.setParentSymbol(kotlinSymbol, for: rangesPackageSymbol)
            }
        }

        // KSP-456: bundled Kotlin sources provide class-returning `until` extensions.
        // The signed `until` matrix here is only a primitive-return fallback; skip
        // any receiver type already covered by bundled source.
        registerSyntheticRangeUntilFunction(
            receiverType: types.intType,
            parameterType: types.intType,
            returnType: types.intType,
            externalLinkName: "__kk_op_rangeUntil",
            rangesPackageSymbol: rangesPackageSymbol,
            rangesFQName: rangesFQName,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticRangeUntilFunction(
            receiverType: types.intType,
            parameterType: types.longType,
            returnType: types.longType,
            externalLinkName: "__kk_op_rangeUntil",
            rangesPackageSymbol: rangesPackageSymbol,
            rangesFQName: rangesFQName,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticRangeUntilFunction(
            receiverType: types.longType,
            parameterType: types.intType,
            returnType: types.longType,
            externalLinkName: "__kk_op_rangeUntil",
            rangesPackageSymbol: rangesPackageSymbol,
            rangesFQName: rangesFQName,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticRangeUntilFunction(
            receiverType: types.longType,
            parameterType: types.longType,
            returnType: types.longType,
            externalLinkName: "__kk_op_rangeUntil",
            rangesPackageSymbol: rangesPackageSymbol,
            rangesFQName: rangesFQName,
            symbols: symbols,
            interner: interner
        )
    }

    private func registerSyntheticRangeUntilFunction(
        receiverType: TypeID,
        parameterType: TypeID,
        returnType: TypeID,
        externalLinkName: String,
        rangesPackageSymbol: SymbolID,
        rangesFQName: [InternedString],
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let types = BundledSyntheticStubRegistration.types else {
            return
        }
        let bundledIndex = BundledSyntheticStubRegistration.bundledIndex
        let functionName = interner.intern("until")
        let functionFQName = rangesFQName + [functionName]

        // KSP-456: bundled Kotlin sources provide class-returning `until` extensions.
        // Skip the synthetic primitive-return stub for any receiver type already
        // covered by bundled source.
        if let owner = BundledDeclarationIndex.receiverOwnerFQName(
            for: receiverType,
            symbols: symbols,
            types: types,
            interner: interner
        ), shouldSkipSyntheticStub(
            bundledIndex: bundledIndex,
            ownerFQName: owner,
            name: functionName,
            arity: 1
        ) {
            return
        }

        let functionSymbol = symbols.define(
            kind: .function,
            name: functionName,
            fqName: functionFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(rangesPackageSymbol, for: functionSymbol)
        symbols.setExternalLinkName(externalLinkName, for: functionSymbol)

        let parameterName = interner.intern("to")
        let parameterSymbol = symbols.define(
            kind: .valueParameter,
            name: parameterName,
            fqName: functionFQName + [parameterName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(functionSymbol, for: parameterSymbol)

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [parameterType],
                returnType: returnType,
                isSuspend: false,
                valueParameterSymbols: [parameterSymbol],
                valueParameterHasDefaultValues: [false],
                valueParameterIsVararg: [false]
            ),
            for: functionSymbol
        )
    }
}
