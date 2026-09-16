import RuntimeABI

// KSP-697: List and AbstractList nominal declarations are source-backed in the
// bundled stdlib. KSP-700 moved the indexed/empty/list-iterator contracts to
// collections/List.kt and collections/MutableList.kt; the Swift registrations
// below retain only the no-stdlib/precompiled fallback for List.get and the
// residual HOF registration delegated to the dedicated helper.

/// Synthetic List residuals retained after the KSP-700 source migration.
extension DataFlowSemaPhase {
    func registerSyntheticListStub(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString],
        collectionInterfaceSymbol: SymbolID,
        bundledIndex: BundledDeclarationIndex = .empty,
        skipStats: SyntheticStubSkipStatsCollector? = nil
    ) -> SymbolID {
        let listName = interner.intern("List")
        let listFQName = kotlinCollectionsPkg + [listName]
        let listInterfaceSymbol: SymbolID = if let existing = symbols.lookup(fqName: listFQName) {
            existing
        } else {
            symbols.define(
                kind: .interface,
                name: listName,
                fqName: listFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }

        let listTypeParamName = interner.intern("E")
        let listTypeParamFQName = listFQName + [listTypeParamName]
        let listTypeParamSymbol = symbols.define(
            kind: .typeParameter,
            name: listTypeParamName,
            fqName: listTypeParamFQName,
            declSite: nil,
            visibility: .private,
            flags: []
        )
        let listTypeParamType = types.make(.typeParam(TypeParamType(
            symbol: listTypeParamSymbol,
            nullability: .nonNull
        )))
        types.setNominalTypeParameterSymbols([listTypeParamSymbol], for: listInterfaceSymbol)
        types.setNominalTypeParameterVariances([.out], for: listInterfaceSymbol)
        symbols.setDirectSupertypes([collectionInterfaceSymbol], for: listInterfaceSymbol)
        types.setNominalDirectSupertypes([collectionInterfaceSymbol], for: listInterfaceSymbol)
        symbols.setSupertypeTypeArgs(
            [.out(listTypeParamType)],
            for: listInterfaceSymbol,
            supertype: collectionInterfaceSymbol
        )
        types.setNominalSupertypeTypeArgs(
            [.out(listTypeParamType)],
            for: listInterfaceSymbol,
            supertype: collectionInterfaceSymbol
        )

        registerListGetOperator(
            symbols: symbols,
            types: types,
            interner: interner,
            listFQName: listFQName,
            listInterfaceSymbol: listInterfaceSymbol,
            listTypeParamSymbol: listTypeParamSymbol,
            listTypeParamType: listTypeParamType,
            bundledIndex: bundledIndex
        )
        registerListTransformMembers(
            symbols: symbols,
            types: types,
            interner: interner,
            listFQName: listFQName,
            listInterfaceSymbol: listInterfaceSymbol,
            listTypeParamSymbol: listTypeParamSymbol,
            listTypeParamType: listTypeParamType,
            collectionInterfaceSymbol: collectionInterfaceSymbol,
            bundledIndex: bundledIndex,
            skipStats: skipStats
        )
        return listInterfaceSymbol
    }

    /// Register the no-stdlib/precompiled fallback for `List.get`.
    /// Bundled source owns the declaration whenever the index contains it.
    private func registerListGetOperator(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        listFQName: [InternedString],
        listInterfaceSymbol: SymbolID,
        listTypeParamSymbol: SymbolID,
        listTypeParamType: TypeID,
        bundledIndex: BundledDeclarationIndex
    ) {
        let listGetName = interner.intern("get")
        let listGetFQName = listFQName + [listGetName]
        guard symbols.lookup(fqName: listGetFQName) == nil,
              !bundledIndex.contains(owner: listFQName, name: listGetName, arity: 1)
        else {
            return
        }

        let listReceiverType = types.make(.classType(ClassType(
            classSymbol: listInterfaceSymbol,
            args: [.out(listTypeParamType)],
            nullability: .nonNull
        )))
        let listGetSymbol = symbols.define(
            kind: .function,
            name: listGetName,
            fqName: listGetFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .operatorFunction]
        )
        symbols.setParentSymbol(listInterfaceSymbol, for: listGetSymbol)
        symbols.setExternalLinkName("__kk_list_get", for: listGetSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: listReceiverType,
                parameterTypes: [types.intType],
                returnType: listTypeParamType,
                typeParameterSymbols: [listTypeParamSymbol],
                classTypeParameterCount: 1
            ),
            for: listGetSymbol
        )
    }

    /// Register `kotlin.collections.AbstractList<E>` for fallback contexts.
    func registerSyntheticAbstractListStub(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString],
        abstractCollectionSymbol: SymbolID,
        listInterfaceSymbol: SymbolID
    ) -> SymbolID {
        let abstractListName = interner.intern("AbstractList")
        let abstractListFQName = kotlinCollectionsPkg + [abstractListName]
        let abstractListSymbol: SymbolID = if let existing = symbols.lookup(fqName: abstractListFQName) {
            existing
        } else {
            symbols.define(
                kind: .class,
                name: abstractListName,
                fqName: abstractListFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .abstractType]
            )
        }

        let typeParamName = interner.intern("E")
        let typeParamFQName = abstractListFQName + [typeParamName]
        let typeParamSymbol: SymbolID = if let existing = symbols.lookup(fqName: typeParamFQName) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: typeParamName,
                fqName: typeParamFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
        }
        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol,
            nullability: .nonNull
        )))
        types.setNominalTypeParameterSymbols([typeParamSymbol], for: abstractListSymbol)
        types.setNominalTypeParameterVariances([.out], for: abstractListSymbol)

        let abstractListType = types.make(.classType(ClassType(
            classSymbol: abstractListSymbol,
            args: [.out(typeParamType)],
            nullability: .nonNull
        )))
        symbols.setPropertyType(abstractListType, for: abstractListSymbol)

        let directSupertypes = [abstractCollectionSymbol, listInterfaceSymbol]
        symbols.setDirectSupertypes(directSupertypes, for: abstractListSymbol)
        types.setNominalDirectSupertypes(directSupertypes, for: abstractListSymbol)
        symbols.setSupertypeTypeArgs(
            [.out(typeParamType)],
            for: abstractListSymbol,
            supertype: abstractCollectionSymbol
        )
        types.setNominalSupertypeTypeArgs(
            [.out(typeParamType)],
            for: abstractListSymbol,
            supertype: abstractCollectionSymbol
        )
        symbols.setSupertypeTypeArgs(
            [.out(typeParamType)],
            for: abstractListSymbol,
            supertype: listInterfaceSymbol
        )
        types.setNominalSupertypeTypeArgs(
            [.out(typeParamType)],
            for: abstractListSymbol,
            supertype: listInterfaceSymbol
        )

        let initName = interner.intern("<init>")
        let initFQName = abstractListFQName + [initName]
        if symbols.lookup(fqName: initFQName) == nil {
            let initSymbol = symbols.define(
                kind: .constructor,
                name: initName,
                fqName: initFQName,
                declSite: nil,
                visibility: .protected,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(abstractListSymbol, for: initSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: nil,
                    parameterTypes: [],
                    returnType: abstractListType,
                    valueParameterSymbols: [],
                    valueParameterHasDefaultValues: [],
                    valueParameterIsVararg: [],
                    typeParameterSymbols: [typeParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: initSymbol
            )
        }

        return abstractListSymbol
    }
}
