import RuntimeABI

// KSP-697: List and AbstractList nominal declarations are source-backed in the
// bundled stdlib. KSP-700 moved the indexed/empty/list-iterator contracts to
// collections/List/List.kt and collections/MutableList.kt; KSP-1063 added the
// `size`/`iterator` redeclarations there. The Swift registrations below retain
// the claimable `size`/`iterator` members (the source decls inherit their
// runtime links — @KsSymbolName cannot annotate a property), plus the
// no-stdlib/precompiled fallback for List.get and the residual HOF
// registration delegated to the dedicated helper.

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
        registerListSizeAndIterator(
            symbols: symbols,
            types: types,
            interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg,
            listFQName: listFQName,
            listInterfaceSymbol: listInterfaceSymbol,
            listTypeParamSymbol: listTypeParamSymbol,
            listTypeParamType: listTypeParamType
        )
        return listInterfaceSymbol
    }

    /// Register the `size`/`iterator` residual members on `kotlin.collections.List`.
    /// Unlike `get`, these must NOT be skipped when bundled source declares them:
    /// the source declarations claim the synthetic symbols (keeping the runtime
    /// link names) the same way `Collection.size`/`Collection.iterator` do —
    /// `@KsSymbolName` cannot attach a link to a property, and an unlinked
    /// source-declared `iterator` would route through virtual itable dispatch
    /// that built-in runtime list boxes never register for (BUG-166).
    private func registerListSizeAndIterator(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString],
        listFQName: [InternedString],
        listInterfaceSymbol: SymbolID,
        listTypeParamSymbol: SymbolID,
        listTypeParamType: TypeID
    ) {
        // Registered inline because size is a .property, not a function.
        // The link is the Collection-level bridge, not __kk_list_size:
        // receivers statically typed List<Int> lower through the
        // unresolved-collection path to __kk_list_size anyway (they defer past
        // the external-link shortcut via shouldDeferCollectionSizePropertyRead),
        // while receivers of a user interface extending List keep the
        // Collection bridge — which unlike __kk_list_size knows how to reach
        // Kotlin-defined implementations via runtimeSourceCollectionSize.
        let sizeName = interner.intern("size")
        let sizeFQName = listFQName + [sizeName]
        if symbols.lookup(fqName: sizeFQName) == nil {
            let sizeSymbol = symbols.define(
                kind: .property,
                name: sizeName,
                fqName: sizeFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(listInterfaceSymbol, for: sizeSymbol)
            symbols.setExternalLinkName("__kk_collection_size", for: sizeSymbol)
            symbols.setPropertyType(types.intType, for: sizeSymbol)
        }

        let iteratorFQName = kotlinCollectionsPkg + [interner.intern("Iterator")]
        let iteratorName = interner.intern("iterator")
        let iteratorMemberFQName = listFQName + [iteratorName]
        if symbols.lookup(fqName: iteratorMemberFQName) == nil,
           let iteratorSymbol = symbols.lookup(fqName: iteratorFQName)
        {
            let iteratorReturnType = types.make(.classType(ClassType(
                classSymbol: iteratorSymbol,
                args: [.out(listTypeParamType)],
                nullability: .nonNull
            )))
            let listReceiverType = types.make(.classType(ClassType(
                classSymbol: listInterfaceSymbol,
                args: [.out(listTypeParamType)],
                nullability: .nonNull
            )))
            let iteratorMemberSymbol = symbols.define(
                kind: .function,
                name: iteratorName,
                fqName: iteratorMemberFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .operatorFunction]
            )
            symbols.setParentSymbol(listInterfaceSymbol, for: iteratorMemberSymbol)
            symbols.setExternalLinkName("kk_list_iterator", for: iteratorMemberSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: listReceiverType,
                    parameterTypes: [],
                    returnType: iteratorReturnType,
                    typeParameterSymbols: [listTypeParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: iteratorMemberSymbol
            )
        }
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
