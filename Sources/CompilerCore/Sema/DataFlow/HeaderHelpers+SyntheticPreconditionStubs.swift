/// Synthetic fallback declarations for kotlin.require, kotlin.check, assert, and error.
/// Source stdlib declarations own these symbols when imported; this fallback only
/// keeps no-stdlib-search Sema paths contract-aware.
extension DataFlowSemaPhase {
    func registerSyntheticPreconditionStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
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
            externalLinkName: "kk_require",
            symbols: symbols,
            interner: interner,
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
            externalLinkName: "kk_require_lazy",
            symbols: symbols,
            interner: interner,
            contractNonNullParameterIndex: 0
        )
        registerSyntheticPreconditionTopLevelFunction(
            named: "check",
            packageFQName: kotlinPkg,
            packageSymbol: packageSymbol,
            parameters: [(name: "condition", type: types.booleanType)],
            returnType: types.unitType,
            externalLinkName: "kk_check",
            symbols: symbols,
            interner: interner,
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
            externalLinkName: "kk_check_lazy",
            symbols: symbols,
            interner: interner,
            contractNonNullParameterIndex: 0
        )
        registerSyntheticPreconditionTopLevelFunction(
            named: "assert",
            packageFQName: kotlinPkg,
            packageSymbol: packageSymbol,
            parameters: [(name: "value", type: types.booleanType)],
            returnType: types.unitType,
            externalLinkName: "kk_precondition_assert",
            symbols: symbols,
            interner: interner,
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
            externalLinkName: "kk_precondition_assert_lazy",
            symbols: symbols,
            interner: interner,
            contractNonNullParameterIndex: 0
        )
        registerSyntheticPreconditionTopLevelFunction(
            named: "error",
            packageFQName: kotlinPkg,
            packageSymbol: packageSymbol,
            parameters: [(name: "message", type: types.anyType)],
            returnType: types.nothingType,
            externalLinkName: "kk_error",
            symbols: symbols,
            interner: interner
        )
    }

    private func registerSyntheticPreconditionTopLevelFunction(
        named name: String,
        packageFQName: [InternedString],
        packageSymbol: SymbolID,
        parameters: [(name: String, type: TypeID)],
        returnType: TypeID,
        externalLinkName: String,
        symbols: SymbolTable,
        interner: StringInterner,
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
            if existingFlags.contains(.synthetic) && !existingFlags.contains(.importedLibrary) {
                symbols.setExternalLinkName(externalLinkName, for: existing)
            }
            setPreconditionContractEffect(
                on: existing,
                parameterIndex: contractNonNullParameterIndex,
                symbols: symbols
            )
            return
        }
        if hasSourceOrImportedLibrarySymbol(fqName: functionFQName, kind: .function, symbols: symbols) {
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
