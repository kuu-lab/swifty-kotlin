extension DataFlowSemaPhase {
    func registerCInteropPinnedStubs(
        cinteropPkg: [InternedString],
        pinnedSymbol: SymbolID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let pinnedFQName = cinteropPkg + [interner.intern("Pinned")]
        let pinnedTypeParameterName = interner.intern("T")
        let pinnedTypeParameterFQName = pinnedFQName + [pinnedTypeParameterName]
        let pinnedTypeParameterSymbol: SymbolID = if let existing = symbols.lookup(fqName: pinnedTypeParameterFQName) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: pinnedTypeParameterName,
                fqName: pinnedTypeParameterFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
        }
        symbols.setTypeParameterUpperBounds([types.anyType], for: pinnedTypeParameterSymbol)
        let pinnedTypeParameterType = types.make(.typeParam(TypeParamType(
            symbol: pinnedTypeParameterSymbol,
            nullability: .nonNull
        )))
        let pinnedType = types.make(.classType(ClassType(
            classSymbol: pinnedSymbol,
            args: [.invariant(pinnedTypeParameterType)],
            nullability: .nonNull
        )))
        symbols.setPropertyType(pinnedType, for: pinnedSymbol)
        types.setNominalTypeParameterSymbols([pinnedTypeParameterSymbol], for: pinnedSymbol)
        types.setNominalTypeParameterVariances([.invariant], for: pinnedSymbol)

        let pinName = interner.intern("pin")
        let pinFQName = cinteropPkg + [pinName]
        let pinTypeParameterName = interner.intern("T")
        let pinTypeParameterFQName = pinFQName + [pinTypeParameterName]
        let pinTypeParameterSymbol: SymbolID = if let existing = symbols.lookup(fqName: pinTypeParameterFQName) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: pinTypeParameterName,
                fqName: pinTypeParameterFQName,
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
        }
        symbols.setTypeParameterUpperBounds([types.anyType], for: pinTypeParameterSymbol)
        let pinTypeParameterType = types.make(.typeParam(TypeParamType(
            symbol: pinTypeParameterSymbol,
            nullability: .nonNull
        )))
        let pinReturnType = types.make(.classType(ClassType(
            classSymbol: pinnedSymbol,
            args: [.invariant(pinTypeParameterType)],
            nullability: .nonNull
        )))
        registerSyntheticNativeTopLevelFunction(
            named: "pin",
            packageFQName: cinteropPkg,
            receiverType: pinTypeParameterType,
            parameters: [],
            returnType: pinReturnType,
            typeParameterSymbols: [pinTypeParameterSymbol],
            typeParameterUpperBoundsList: [[types.anyType]],
            externalLinkName: "kk_pin_object",
            flags: [.synthetic, .inlineFunction],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticNativeMemberFunction(
            named: "get",
            ownerSymbol: pinnedSymbol,
            receiverType: pinnedType,
            parameters: [],
            returnType: pinnedTypeParameterType,
            typeParameterSymbols: [pinnedTypeParameterSymbol],
            typeParameterUpperBoundsList: [[types.anyType]],
            classTypeParameterCount: 1,
            externalLinkName: "kk_pinned_get",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticNativeMemberFunction(
            named: "unpin",
            ownerSymbol: pinnedSymbol,
            receiverType: pinnedType,
            parameters: [],
            returnType: types.unitType,
            typeParameterSymbols: [pinnedTypeParameterSymbol],
            typeParameterUpperBoundsList: [[types.anyType]],
            classTypeParameterCount: 1,
            externalLinkName: "kk_unpin_object",
            symbols: symbols,
            interner: interner
        )
    }

    func registerCInteropUsePinnedStub(
        cinteropPkg: [InternedString],
        cinteropPkgSymbol: SymbolID?,
        pinnedSymbol: SymbolID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        // Special-cased as a scope function (like Closeable.use); inline-expanded
        // by CallLowerer, no runtime call for usePinned itself.
        let usePinnedName = interner.intern("usePinned")
        let usePinnedFQName = cinteropPkg + [usePinnedName]
        if symbols.lookup(fqName: usePinnedFQName) == nil {
            let usePinnedTypeParameterName = interner.intern("T")
            let usePinnedReturnTypeParameterName = interner.intern("R")
            let usePinnedTypeParameterSymbol = symbols.define(
                kind: .typeParameter,
                name: usePinnedTypeParameterName,
                fqName: usePinnedFQName + [usePinnedTypeParameterName],
                declSite: nil,
                visibility: .private,
                flags: []
            )
            let usePinnedReturnTypeParameterSymbol = symbols.define(
                kind: .typeParameter,
                name: usePinnedReturnTypeParameterName,
                fqName: usePinnedFQName + [usePinnedReturnTypeParameterName],
                declSite: nil,
                visibility: .private,
                flags: []
            )
            symbols.setTypeParameterUpperBounds([types.anyType], for: usePinnedTypeParameterSymbol)

            let usePinnedTypeParameterType = types.make(.typeParam(TypeParamType(
                symbol: usePinnedTypeParameterSymbol,
                nullability: .nonNull
            )))
            let usePinnedReturnTypeParameterType = types.make(.typeParam(TypeParamType(
                symbol: usePinnedReturnTypeParameterSymbol,
                nullability: .nonNull
            )))
            let usePinnedBlockParameterType = types.make(.classType(ClassType(
                classSymbol: pinnedSymbol,
                args: [.invariant(usePinnedTypeParameterType)],
                nullability: .nonNull
            )))
            let usePinnedBlockType = types.make(.functionType(FunctionType(
                params: [usePinnedBlockParameterType],
                returnType: usePinnedReturnTypeParameterType,
                isSuspend: false,
                nullability: .nonNull
            )))

            let usePinnedBlockParamName = interner.intern("block")
            let usePinnedBlockParamSymbol = symbols.define(
                kind: .valueParameter,
                name: usePinnedBlockParamName,
                fqName: usePinnedFQName + [usePinnedBlockParamName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )

            let usePinnedSymbol = symbols.define(
                kind: .function,
                name: usePinnedName,
                fqName: usePinnedFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .inlineFunction]
            )
            if let cinteropPkgSymbol {
                symbols.setParentSymbol(cinteropPkgSymbol, for: usePinnedSymbol)
            }
            symbols.setParentSymbol(usePinnedSymbol, for: usePinnedTypeParameterSymbol)
            symbols.setParentSymbol(usePinnedSymbol, for: usePinnedReturnTypeParameterSymbol)
            symbols.setParentSymbol(usePinnedSymbol, for: usePinnedBlockParamSymbol)

            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: usePinnedTypeParameterType,
                    parameterTypes: [usePinnedBlockType],
                    returnType: usePinnedReturnTypeParameterType,
                    isSuspend: false,
                    valueParameterSymbols: [usePinnedBlockParamSymbol],
                    valueParameterHasDefaultValues: [false],
                    valueParameterIsVararg: [false],
                    typeParameterSymbols: [usePinnedTypeParameterSymbol, usePinnedReturnTypeParameterSymbol],
                    typeParameterUpperBoundsList: [[types.anyType], []],
                    classTypeParameterCount: 0
                ),
                for: usePinnedSymbol
            )
        }
    }
}
