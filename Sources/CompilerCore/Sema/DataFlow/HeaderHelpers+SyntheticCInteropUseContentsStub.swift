extension DataFlowSemaPhase {
    /// fun <T : CStructVar, R> CValue<T>.useContents(block: T.() -> R): R
    ///
    /// Kotlin/Native declares this as a top-level extension that user code must
    /// import (`import kotlinx.cinterop.useContents`). The call itself is
    /// intercepted as a scope function before overload resolution (see
    /// `scopeUseContents`), so this symbol only exists to make the import
    /// resolve; without it `ScopeBuilder` reports KSWIFTK-SEMA-UNRESOLVED-IMPORT.
    func registerCInteropUseContentsStub(
        cinteropPkg: [InternedString],
        cinteropPkgSymbol: SymbolID?,
        cValueSymbol: SymbolID,
        cStructVarSymbol: SymbolID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let useContentsName = interner.intern("useContents")
        let useContentsFQName = cinteropPkg + [useContentsName]
        guard symbols.lookup(fqName: useContentsFQName) == nil else { return }

        let typeParameterName = interner.intern("T")
        let returnTypeParameterName = interner.intern("R")
        let typeParameterSymbol = symbols.define(
            kind: .typeParameter,
            name: typeParameterName,
            fqName: useContentsFQName + [typeParameterName],
            declSite: nil,
            visibility: .private,
            flags: []
        )
        let returnTypeParameterSymbol = symbols.define(
            kind: .typeParameter,
            name: returnTypeParameterName,
            fqName: useContentsFQName + [returnTypeParameterName],
            declSite: nil,
            visibility: .private,
            flags: []
        )
        let cStructVarType = types.make(.classType(ClassType(
            classSymbol: cStructVarSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setTypeParameterUpperBounds([cStructVarType], for: typeParameterSymbol)

        let typeParameterType = types.make(.typeParam(TypeParamType(
            symbol: typeParameterSymbol,
            nullability: .nonNull
        )))
        let returnTypeParameterType = types.make(.typeParam(TypeParamType(
            symbol: returnTypeParameterSymbol,
            nullability: .nonNull
        )))
        let receiverType = types.make(.classType(ClassType(
            classSymbol: cValueSymbol,
            args: [.invariant(typeParameterType)],
            nullability: .nonNull
        )))
        let blockType = types.make(.functionType(FunctionType(
            receiver: typeParameterType,
            params: [],
            returnType: returnTypeParameterType,
            isSuspend: false,
            nullability: .nonNull
        )))

        let blockParamName = interner.intern("block")
        let blockParamSymbol = symbols.define(
            kind: .valueParameter,
            name: blockParamName,
            fqName: useContentsFQName + [blockParamName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        let useContentsSymbol = symbols.define(
            kind: .function,
            name: useContentsName,
            fqName: useContentsFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .inlineFunction]
        )
        if let cinteropPkgSymbol {
            symbols.setParentSymbol(cinteropPkgSymbol, for: useContentsSymbol)
        }
        symbols.setParentSymbol(useContentsSymbol, for: typeParameterSymbol)
        symbols.setParentSymbol(useContentsSymbol, for: returnTypeParameterSymbol)
        symbols.setParentSymbol(useContentsSymbol, for: blockParamSymbol)

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [blockType],
                returnType: returnTypeParameterType,
                isSuspend: false,
                valueParameterSymbols: [blockParamSymbol],
                valueParameterHasDefaultValues: [false],
                valueParameterIsVararg: [false],
                typeParameterSymbols: [typeParameterSymbol, returnTypeParameterSymbol],
                typeParameterUpperBoundsList: [[cStructVarType], []],
                classTypeParameterCount: 0
            ),
            for: useContentsSymbol
        )
    }
}
