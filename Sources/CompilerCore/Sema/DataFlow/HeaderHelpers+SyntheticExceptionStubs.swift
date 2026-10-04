
extension DataFlowSemaPhase {
    func registerSyntheticExceptionStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinPkg: [InternedString]
    ) {
        // KSP-656 moves the Kotlin common exception hierarchy to bundled source.
        // Keep only the platform-specific and coroutine-specific residual types
        // here; source-backed classes must not be recreated as synthetic symbols.
        // kotlin.text.CharacterCodingException is source-backed by
        // Stdlib/kotlin/text/CharacterCodingException.kt.
        let nullableStringType = types.makeNullable(types.stringType)

        // NegativeArraySizeException is a JVM/platform-specific residual;
        // ArrayIndexOutOfBoundsException is now source-backed by
        // Stdlib/kotlin/ArrayIndexOutOfBoundsException.kt.

        let runtimeExceptionSymbol = ensureClassSymbol(
            named: "RuntimeException",
            in: kotlinPkg,
            symbols: symbols,
            interner: interner
        )
        let negativeArraySizeSymbol = ensureClassSymbol(
            named: "NegativeArraySizeException",
            in: kotlinPkg,
            symbols: symbols,
            interner: interner
        )
        symbols.setDirectSupertypes([runtimeExceptionSymbol], for: negativeArraySizeSymbol)
        types.setNominalDirectSupertypes([runtimeExceptionSymbol], for: negativeArraySizeSymbol)
        let negativeArraySizeType = types.make(.classType(ClassType(
            classSymbol: negativeArraySizeSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(negativeArraySizeType, for: negativeArraySizeSymbol)
        symbols.insertFlags(.openType, for: negativeArraySizeSymbol)
        registerSyntheticPlatformExceptionConstructor(
            ownerSymbol: negativeArraySizeSymbol,
            ownerType: negativeArraySizeType,
            parameters: [],
            externalLinkName: "kk_negative_array_size_exception_new",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticPlatformExceptionConstructor(
            ownerSymbol: negativeArraySizeSymbol,
            ownerType: negativeArraySizeType,
            parameters: [("message", nullableStringType)],
            externalLinkName: "kk_negative_array_size_exception_new_message",
            symbols: symbols,
            interner: interner
        )

    }

    // Used only by residual platform/coroutine exception stubs. KSP-656's
    // common exception constructors are declared directly in bundled Kotlin source.
    func registerSyntheticPlatformExceptionConstructors(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        includeMessageOverload: Bool,
        throwableSymbol: SymbolID? = nil,
        noArgLinkName: String = "__kk_throwable_new",
        messageLinkName: String = "__kk_throwable_new",
        messageCauseLinkName: String = "__kk_throwable_new_with_cause"
    ) {
        registerSyntheticPlatformExceptionConstructor(
            ownerSymbol: ownerSymbol,
            ownerType: ownerType,
            parameters: [],
            externalLinkName: noArgLinkName,
            symbols: symbols,
            interner: interner
        )
        if includeMessageOverload {
            registerSyntheticPlatformExceptionConstructor(
                ownerSymbol: ownerSymbol,
                ownerType: ownerType,
                parameters: [("message", types.stringType)],
                externalLinkName: messageLinkName,
                symbols: symbols,
                interner: interner
            )
        }
        if includeMessageOverload, let throwableSymbol {
            let nullableThrowableType = types.make(.classType(ClassType(
                classSymbol: throwableSymbol,
                args: [],
                nullability: .nullable
            )))
            registerSyntheticPlatformExceptionConstructor(
                ownerSymbol: ownerSymbol,
                ownerType: ownerType,
                parameters: [("message", types.stringType), ("cause", nullableThrowableType)],
                externalLinkName: messageCauseLinkName,
                symbols: symbols,
                interner: interner
            )
        }
    }

    func registerSyntheticPlatformExceptionConstructor(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        parameters: [(name: String, type: TypeID)],
        externalLinkName: String,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }
        let initName = interner.intern("<init>")
        let ctorFQName = ownerInfo.fqName + [initName]
        let hasMatchingConstructor = symbols.lookupAll(fqName: ctorFQName).contains { symbolID in
            guard let symbol = symbols.symbol(symbolID),
                  symbol.kind == .constructor,
                  let signature = symbols.functionSignature(for: symbolID)
            else {
                return false
            }
            return signature.parameterTypes == parameters.map(\.type)
        }
        guard !hasMatchingConstructor else {
            return
        }

        let ctorSymbol = symbols.define(
            kind: .constructor,
            name: initName,
            fqName: ctorFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(ownerSymbol, for: ctorSymbol)
        symbols.setExternalLinkName(externalLinkName, for: ctorSymbol)

        var valueParameterSymbols: [SymbolID] = []
        for parameter in parameters {
            let parameterName = interner.intern(parameter.name)
            let paramSymbol = symbols.define(
                kind: .valueParameter,
                name: parameterName,
                fqName: ctorFQName + [parameterName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(ctorSymbol, for: paramSymbol)
            valueParameterSymbols.append(paramSymbol)
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: parameters.map(\.type),
                returnType: ownerType,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: valueParameterSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count)
            ),
            for: ctorSymbol
        )
    }
}
