/// Early synthetic anchor for `kotlin.Result`.
///
/// Coroutine stubs are registered before bundled source headers, and
/// `Continuation.resumeWith(Result<T>)` needs the `Result` nominal symbol during
/// that pass. The actual Result API surface is now collected from
/// `Stdlib/kotlin/Result.kt`. This helper registers only the private ABI bridge
/// functions that the Kotlin source wrappers call.
extension DataFlowSemaPhase {
    func registerSyntheticResultStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinPkg: [InternedString] = [interner.intern("kotlin")]
        let resultSymbol = ensureClassSymbol(named: "Result", in: kotlinPkg, symbols: symbols, interner: interner)

        let tName = interner.intern("T")
        let resultFQName = kotlinPkg + [interner.intern("Result")]
        let tFQName = resultFQName + [tName]
        let tSymbol: SymbolID
        if let existing = symbols.lookup(fqName: tFQName) {
            tSymbol = existing
        } else {
            tSymbol = symbols.define(
                kind: .typeParameter,
                name: tName,
                fqName: tFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
            symbols.setParentSymbol(resultSymbol, for: tSymbol)
        }

        let tType = types.make(.typeParam(TypeParamType(symbol: tSymbol, nullability: .nonNull)))
        let resultType = types.make(.classType(ClassType(
            classSymbol: resultSymbol,
            args: [.invariant(tType)],
            nullability: .nonNull
        )))
        types.setNominalTypeParameterSymbols([tSymbol], for: resultSymbol)
        types.setNominalTypeParameterVariances([.invariant], for: resultSymbol)
        symbols.setPropertyType(resultType, for: resultSymbol)

        let nullableTType = types.makeNullable(tType)
        let throwableSymbol = ensureClassSymbol(named: "Throwable", in: kotlinPkg, symbols: symbols, interner: interner)
        let throwableType = types.make(.classType(ClassType(
            classSymbol: throwableSymbol,
            args: [],
            nullability: .nonNull
        )))
        let nullableThrowableType = types.makeNullable(throwableType)
        let unitType = types.unitType
        let boolType = types.booleanType

        func functionType(params: [TypeID], returnType: TypeID) -> TypeID {
            types.make(.functionType(FunctionType(
                params: params,
                returnType: returnType,
                nullability: .nonNull
            )))
        }

        func makeResultType(for elementType: TypeID) -> TypeID {
            types.make(.classType(ClassType(
                classSymbol: resultSymbol,
                args: [.invariant(elementType)],
                nullability: .nonNull
            )))
        }

        func defineTypeParameter(named name: String, under ownerFQName: [InternedString]) -> (SymbolID, TypeID) {
            let internedName = interner.intern(name)
            let fqName = ownerFQName + [internedName]
            let symbol: SymbolID = if let existing = symbols.lookup(fqName: fqName) {
                existing
            } else {
                symbols.define(
                    kind: .typeParameter,
                    name: internedName,
                    fqName: fqName,
                    declSite: nil,
                    visibility: .private,
                    flags: [.synthetic]
                )
            }
            let type = types.make(.typeParam(TypeParamType(symbol: symbol, nullability: .nonNull)))
            return (symbol, type)
        }

        func defineValueParameters(
            for functionSymbol: SymbolID,
            functionFQName: [InternedString],
            parameterTypes: [TypeID]
        ) -> [SymbolID] {
            parameterTypes.enumerated().map { index, type in
                let name = interner.intern("p\(index)")
                let fqName = functionFQName + [name]
                let parameterSymbol = symbols.define(
                    kind: .valueParameter,
                    name: name,
                    fqName: fqName,
                    declSite: nil,
                    visibility: .private,
                    flags: [.synthetic]
                )
                symbols.setParentSymbol(functionSymbol, for: parameterSymbol)
                symbols.setPropertyType(type, for: parameterSymbol)
                return parameterSymbol
            }
        }

        func registerTopLevelBridge(
            named name: String,
            externalLinkName: String,
            parameterTypes: [TypeID],
            returnType: TypeID,
            typeParameterSymbols: [SymbolID] = []
        ) {
            let functionName = interner.intern(name)
            let functionFQName = kotlinPkg + [functionName]
            let functionSymbol: SymbolID
            if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
                symbols.symbol(symbolID)?.kind == .function
            }) {
                functionSymbol = existing
            } else {
                functionSymbol = symbols.define(
                    kind: .function,
                    name: functionName,
                    fqName: functionFQName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic]
                )
            }
            symbols.setExternalLinkName(externalLinkName, for: functionSymbol)
            let parameterSymbols = defineValueParameters(
                for: functionSymbol,
                functionFQName: functionFQName,
                parameterTypes: parameterTypes
            )
            for typeParameterSymbol in typeParameterSymbols {
                symbols.setParentSymbol(functionSymbol, for: typeParameterSymbol)
            }
            symbols.setFunctionSignature(
                FunctionSignature(
                    parameterTypes: parameterTypes,
                    returnType: returnType,
                    valueParameterSymbols: parameterSymbols,
                    valueParameterHasDefaultValues: Array(repeating: false, count: parameterTypes.count),
                    valueParameterIsVararg: Array(repeating: false, count: parameterTypes.count),
                    typeParameterSymbols: typeParameterSymbols
                ),
                for: functionSymbol
            )
        }

        func registerMemberBridge(
            named name: String,
            externalLinkName: String,
            parameterTypes: [TypeID],
            returnType: TypeID,
            ownTypeParameterSymbols: [SymbolID] = []
        ) {
            let functionName = interner.intern(name)
            let functionFQName = resultFQName + [functionName]
            let functionSymbol: SymbolID
            if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
                symbols.symbol(symbolID)?.kind == .function
            }) {
                functionSymbol = existing
            } else {
                functionSymbol = symbols.define(
                    kind: .function,
                    name: functionName,
                    fqName: functionFQName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic]
                )
                symbols.setParentSymbol(resultSymbol, for: functionSymbol)
            }
            symbols.setExternalLinkName(externalLinkName, for: functionSymbol)
            let parameterSymbols = defineValueParameters(
                for: functionSymbol,
                functionFQName: functionFQName,
                parameterTypes: parameterTypes
            )
            for typeParameterSymbol in ownTypeParameterSymbols {
                symbols.setParentSymbol(functionSymbol, for: typeParameterSymbol)
            }
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: resultType,
                    parameterTypes: parameterTypes,
                    returnType: returnType,
                    valueParameterSymbols: parameterSymbols,
                    valueParameterHasDefaultValues: Array(repeating: false, count: parameterTypes.count),
                    valueParameterIsVararg: Array(repeating: false, count: parameterTypes.count),
                    typeParameterSymbols: [tSymbol] + ownTypeParameterSymbols,
                    classTypeParameterCount: 1
                ),
                for: functionSymbol
            )
        }

        let runCatchingFQName = kotlinPkg + [interner.intern("__kk_runCatching")]
        let (runTParam, runTType) = defineTypeParameter(named: "T", under: runCatchingFQName)
        registerTopLevelBridge(
            named: "__kk_runCatching",
            externalLinkName: "kk_runCatching",
            parameterTypes: [functionType(params: [], returnType: runTType)],
            returnType: makeResultType(for: runTType),
            typeParameterSymbols: [runTParam]
        )

        registerMemberBridge(
            named: "__kk_result_isSuccess",
            externalLinkName: "kk_result_isSuccess",
            parameterTypes: [],
            returnType: boolType
        )
        registerMemberBridge(
            named: "__kk_result_isFailure",
            externalLinkName: "kk_result_isFailure",
            parameterTypes: [],
            returnType: boolType
        )
        registerMemberBridge(
            named: "__kk_result_getOrNull",
            externalLinkName: "kk_result_getOrNull",
            parameterTypes: [],
            returnType: nullableTType
        )
        registerMemberBridge(
            named: "__kk_result_getOrDefault",
            externalLinkName: "kk_result_getOrDefault",
            parameterTypes: [tType],
            returnType: tType
        )
        registerMemberBridge(
            named: "__kk_result_getOrElse",
            externalLinkName: "kk_result_getOrElse",
            parameterTypes: [functionType(params: [throwableType], returnType: tType)],
            returnType: tType
        )
        registerMemberBridge(
            named: "__kk_result_getOrThrow",
            externalLinkName: "kk_result_getOrThrow",
            parameterTypes: [],
            returnType: tType
        )
        registerMemberBridge(
            named: "__kk_result_exceptionOrNull",
            externalLinkName: "kk_result_exceptionOrNull",
            parameterTypes: [],
            returnType: nullableThrowableType
        )

        let mapFQName = resultFQName + [interner.intern("__kk_result_map")]
        let (mapRParam, mapRType) = defineTypeParameter(named: "R", under: mapFQName)
        registerMemberBridge(
            named: "__kk_result_map",
            externalLinkName: "kk_result_map",
            parameterTypes: [functionType(params: [tType], returnType: mapRType)],
            returnType: makeResultType(for: mapRType),
            ownTypeParameterSymbols: [mapRParam]
        )

        let foldFQName = resultFQName + [interner.intern("__kk_result_fold")]
        let (foldRParam, foldRType) = defineTypeParameter(named: "R", under: foldFQName)
        registerMemberBridge(
            named: "__kk_result_fold",
            externalLinkName: "kk_result_fold",
            parameterTypes: [
                functionType(params: [tType], returnType: foldRType),
                functionType(params: [throwableType], returnType: foldRType),
            ],
            returnType: foldRType,
            ownTypeParameterSymbols: [foldRParam]
        )

        registerMemberBridge(
            named: "__kk_result_onSuccess",
            externalLinkName: "kk_result_onSuccess",
            parameterTypes: [functionType(params: [tType], returnType: unitType)],
            returnType: resultType
        )
        registerMemberBridge(
            named: "__kk_result_onFailure",
            externalLinkName: "kk_result_onFailure",
            parameterTypes: [functionType(params: [throwableType], returnType: unitType)],
            returnType: resultType
        )
        let recoverFQName = resultFQName + [interner.intern("__kk_result_recover")]
        let (recoverRParam, recoverRType) = defineTypeParameter(named: "R", under: recoverFQName)
        registerMemberBridge(
            named: "__kk_result_recover",
            externalLinkName: "kk_result_recover",
            parameterTypes: [functionType(params: [throwableType], returnType: recoverRType)],
            returnType: makeResultType(for: recoverRType),
            ownTypeParameterSymbols: [recoverRParam]
        )
        let recoverCatchingFQName = resultFQName + [interner.intern("__kk_result_recoverCatching")]
        let (recoverCatchingRParam, recoverCatchingRType) = defineTypeParameter(
            named: "R",
            under: recoverCatchingFQName
        )
        registerMemberBridge(
            named: "__kk_result_recoverCatching",
            externalLinkName: "kk_result_recoverCatching",
            parameterTypes: [functionType(params: [throwableType], returnType: recoverCatchingRType)],
            returnType: makeResultType(for: recoverCatchingRType),
            ownTypeParameterSymbols: [recoverCatchingRParam]
        )
    }
}
