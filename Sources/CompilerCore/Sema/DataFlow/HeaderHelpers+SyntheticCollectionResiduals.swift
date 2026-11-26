// swiftlint:disable file_length

extension DataFlowSemaPhase {
    func registerSyntheticCollectionStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        bundledIndex: BundledDeclarationIndex = .empty,
        skipStats: SyntheticStubSkipStatsCollector? = nil
    ) {
        let kotlinPkg: [InternedString] = [interner.intern("kotlin")]
        if symbols.lookup(fqName: kotlinPkg) == nil {
            _ = symbols.define(
                kind: .package,
                name: interner.intern("kotlin"),
                fqName: kotlinPkg,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }

        let kotlinCollectionsPkg: [InternedString] = [interner.intern("kotlin"), interner.intern("collections")]
        if symbols.lookup(fqName: kotlinCollectionsPkg) == nil {
            _ = symbols.define(
                kind: .package,
                name: interner.intern("collections"),
                fqName: kotlinCollectionsPkg,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }

        registerSyntheticRandomAccessStub(
            symbols: symbols,
            types: types,
            interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg
        )

        let iterableInterfaceSymbol = registerSyntheticIterableStub(
            symbols: symbols, types: types, interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg
        )

        let collectionInterfaceSymbol = registerSyntheticCollectionStub(
            symbols: symbols, types: types, interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg,
            iterableInterfaceSymbol: iterableInterfaceSymbol,
            bundledIndex: bundledIndex,
            skipStats: skipStats
        )

        let abstractCollectionSymbol = registerSyntheticAbstractCollectionStub(
            symbols: symbols, types: types, interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg,
            collectionInterfaceSymbol: collectionInterfaceSymbol
        )

        let mutableIterableInterfaceSymbol = registerSyntheticMutableIterableStub(
            symbols: symbols, types: types, interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg,
            iterableInterfaceSymbol: iterableInterfaceSymbol
        )

        let mutableCollectionInterfaceSymbol = registerSyntheticMutableCollectionStub(
            symbols: symbols, types: types, interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg,
            collectionInterfaceSymbol: collectionInterfaceSymbol,
            mutableIterableInterfaceSymbol: mutableIterableInterfaceSymbol
        )

        registerSyntheticAbstractMutableCollectionStub(
            symbols: symbols, types: types, interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg,
            collectionInterfaceSymbol: collectionInterfaceSymbol,
            mutableCollectionInterfaceSymbol: mutableCollectionInterfaceSymbol
        )

        let listInterfaceSymbol = registerSyntheticListStub(
            symbols: symbols, types: types, interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg,
            collectionInterfaceSymbol: collectionInterfaceSymbol,
            bundledIndex: bundledIndex)

        _ = registerSyntheticAbstractListStub(
            symbols: symbols, types: types, interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg,
            abstractCollectionSymbol: abstractCollectionSymbol,
            listInterfaceSymbol: listInterfaceSymbol
        )

        registerSyntheticMutableListStub(
            symbols: symbols, types: types, interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg,
            listInterfaceSymbol: listInterfaceSymbol,
            mutableCollectionInterfaceSymbol: mutableCollectionInterfaceSymbol,
            mutableIterableInterfaceSymbol: mutableIterableInterfaceSymbol
        )

        registerSyntheticMapEntryResiduals(
            symbols: symbols,
            types: types,
            interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg,
            bundledIndex: bundledIndex
        )
        registerSyntheticMapRuntimeResiduals(
            symbols: symbols,
            types: types,
            interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg,
            bundledIndex: bundledIndex
        )

        registerMutableCollectionArrayAddAllMembers(
            symbols: symbols,
            types: types,
            interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg
        )

        _ = registerSyntheticSequenceStub(
            packageFQName: [interner.intern("kotlin"), interner.intern("sequences")],
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    private func registerSyntheticRandomAccessStub(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString]
    ) {
        let randomAccessSymbol = ensureInterfaceSymbol(
            named: "RandomAccess",
            in: kotlinCollectionsPkg,
            symbols: symbols,
            interner: interner
        )
        let randomAccessType = types.make(.classType(ClassType(
            classSymbol: randomAccessSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(randomAccessType, for: randomAccessSymbol)
    }


}
