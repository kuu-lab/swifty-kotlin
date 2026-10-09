/// Source-backed MutableList and AbstractMutableList retain nominal bootstrap
/// metadata for cached artifacts and the MutableIterable compatibility edge.
/// Sorting, shuffle, and reverse are bundled Kotlin extensions.
extension DataFlowSemaPhase {

    func registerSyntheticMutableListStub(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString],
        listInterfaceSymbol: SymbolID,
        collectionInterfaceSymbol: SymbolID,
        mutableCollectionInterfaceSymbol: SymbolID,
        mutableIterableInterfaceSymbol: SymbolID
    ) {
        let listTypeParamName = interner.intern("E")
        let mutableListName = interner.intern("MutableList")
        let mutableListFQName = kotlinCollectionsPkg + [mutableListName]
        let mutableListInterfaceSymbol: SymbolID = if let existing = symbols.lookup(fqName: mutableListFQName) {
            existing
        } else {
            symbols.define(
                kind: .interface,
                name: mutableListName,
                fqName: mutableListFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        // Define type parameter E for MutableList<E>
        let mlTypeParamFQName = mutableListFQName + [listTypeParamName]
        let mlTypeParamSymbol = symbols.define(
            kind: .typeParameter,
            name: listTypeParamName,
            fqName: mlTypeParamFQName,
            declSite: nil,
            visibility: .private,
            flags: []
        )
        let mlTypeParamType = types.make(.typeParam(TypeParamType(
            symbol: mlTypeParamSymbol, nullability: .nonNull
        )))
        types.setNominalTypeParameterSymbols([mlTypeParamSymbol], for: mutableListInterfaceSymbol)
        types.setNominalTypeParameterVariances([.invariant], for: mutableListInterfaceSymbol)
        symbols.setDirectSupertypes(
            [listInterfaceSymbol, mutableCollectionInterfaceSymbol, mutableIterableInterfaceSymbol],
            for: mutableListInterfaceSymbol
        )
        types.setNominalDirectSupertypes(
            [listInterfaceSymbol, mutableCollectionInterfaceSymbol, mutableIterableInterfaceSymbol],
            for: mutableListInterfaceSymbol
        )
        symbols.setSupertypeTypeArgs([.out(mlTypeParamType)], for: mutableListInterfaceSymbol, supertype: listInterfaceSymbol)
        types.setNominalSupertypeTypeArgs([.out(mlTypeParamType)], for: mutableListInterfaceSymbol, supertype: listInterfaceSymbol)
        symbols.setSupertypeTypeArgs([.invariant(mlTypeParamType)], for: mutableListInterfaceSymbol, supertype: mutableCollectionInterfaceSymbol)
        types.setNominalSupertypeTypeArgs([.invariant(mlTypeParamType)], for: mutableListInterfaceSymbol, supertype: mutableCollectionInterfaceSymbol)
        symbols.setSupertypeTypeArgs([.invariant(mlTypeParamType)], for: mutableListInterfaceSymbol, supertype: mutableIterableInterfaceSymbol)
        types.setNominalSupertypeTypeArgs([.invariant(mlTypeParamType)], for: mutableListInterfaceSymbol, supertype: mutableIterableInterfaceSymbol)

        _ = registerSyntheticAbstractMutableListStub(
            symbols: symbols,
            types: types,
            interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg,
            listInterfaceSymbol: listInterfaceSymbol,
            mutableListInterfaceSymbol: mutableListInterfaceSymbol
        )
    }

    /// Restore the shared MutableIterable residual edge after a bundled
    /// MutableList source declaration is bound. The source declaration owns
    /// List/MutableCollection, while the compiler shell still supplies the
    /// residual MutableIterable compatibility edge.
    func patchSourceBackedMutableListSupertypes(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let collectionsPackage = [interner.intern("kotlin"), interner.intern("collections")]
        let mutableListName = interner.intern("MutableList")
        let mutableIterableName = interner.intern("MutableIterable")
        guard let mutableListSymbol = symbols.lookup(fqName: collectionsPackage + [mutableListName]),
              let mutableListInfo = symbols.symbol(mutableListSymbol),
              !mutableListInfo.flags.contains(.synthetic),
              let mutableIterableSymbol = symbols.lookup(fqName: collectionsPackage + [mutableIterableName]),
              let typeParameter = types.nominalTypeParameterSymbols(for: mutableListSymbol).first
        else {
            return
        }

        let directSupertypes = symbols.directSupertypes(for: mutableListSymbol)
        guard !directSupertypes.contains(mutableIterableSymbol) else {
            return
        }
        let patchedSupertypes = Array(Set(directSupertypes + [mutableIterableSymbol]))
            .sorted(by: { $0.rawValue < $1.rawValue })
        symbols.setDirectSupertypes(patchedSupertypes, for: mutableListSymbol)
        types.setNominalDirectSupertypes(patchedSupertypes, for: mutableListSymbol)

        let typeParameterType = types.make(.typeParam(TypeParamType(
            symbol: typeParameter,
            nullability: .nonNull
        )))
        let mutableIterableTypeArgs: [TypeArg] = [.invariant(typeParameterType)]
        symbols.setSupertypeTypeArgs(
            mutableIterableTypeArgs,
            for: mutableListSymbol,
            supertype: mutableIterableSymbol
        )
        types.setNominalSupertypeTypeArgs(
            mutableIterableTypeArgs,
            for: mutableListSymbol,
            supertype: mutableIterableSymbol
        )
    }

    /// Register `kotlin.collections.AbstractMutableList<E>` surface (STDLIB-COL-ABSTRACT-006).
    func registerSyntheticAbstractMutableListStub(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString],
        listInterfaceSymbol: SymbolID,
        mutableListInterfaceSymbol: SymbolID
    ) -> SymbolID {
        let abstractMutableListName = interner.intern("AbstractMutableList")
        let abstractMutableListFQName = kotlinCollectionsPkg + [abstractMutableListName]
        let abstractMutableListSymbol: SymbolID = if let existing = symbols.lookup(fqName: abstractMutableListFQName) {
            existing
        } else {
            symbols.define(
                kind: .class,
                name: abstractMutableListName,
                fqName: abstractMutableListFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .abstractType]
            )
        }

        let typeParamSymbol = ensureSyntheticTypeParameterSymbol(
            named: "E",
            in: abstractMutableListFQName,
            symbols: symbols,
            interner: interner
        )
        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol,
            nullability: .nonNull
        )))
        types.setNominalTypeParameterSymbols([typeParamSymbol], for: abstractMutableListSymbol)
        types.setNominalTypeParameterVariances([.invariant], for: abstractMutableListSymbol)

        let abstractMutableListType = types.make(.classType(ClassType(
            classSymbol: abstractMutableListSymbol,
            args: [.invariant(typeParamType)],
            nullability: .nonNull
        )))
        symbols.setPropertyType(abstractMutableListType, for: abstractMutableListSymbol)

        // KSP-929 gave AbstractMutableList a bundled source declaration
        // (`AbstractMutableCollection<E>(), MutableList<E>`). Mirror that shape
        // here rather than the pre-KSP-929 `AbstractList`-based fallback: a
        // .kklib consumer never re-runs bindInheritanceEdges over the bundled
        // source, so this bootstrap edge is the only one it sees, and a stale
        // AbstractList edge broke transitive MutableCollection/MutableIterable
        // subtyping for every concrete AbstractMutableList subclass (ArrayList,
        // HashSet's own AbstractMutableSet sibling, etc.) compiled against a
        // cached artifact.
        let abstractMutableCollectionSymbol = symbols.lookup(
            fqName: kotlinCollectionsPkg + [interner.intern("AbstractMutableCollection")]
        )
        let firstSupertype = abstractMutableCollectionSymbol ?? listInterfaceSymbol
        symbols.setDirectSupertypes([firstSupertype, mutableListInterfaceSymbol], for: abstractMutableListSymbol)
        types.setNominalDirectSupertypes([firstSupertype, mutableListInterfaceSymbol], for: abstractMutableListSymbol)
        symbols.setSupertypeTypeArgs([.invariant(typeParamType)], for: abstractMutableListSymbol, supertype: firstSupertype)
        types.setNominalSupertypeTypeArgs([.invariant(typeParamType)], for: abstractMutableListSymbol, supertype: firstSupertype)
        symbols.setSupertypeTypeArgs([.invariant(typeParamType)], for: abstractMutableListSymbol, supertype: mutableListInterfaceSymbol)
        types.setNominalSupertypeTypeArgs(
            [.invariant(typeParamType)],
            for: abstractMutableListSymbol,
            supertype: mutableListInterfaceSymbol
        )

        let initName = interner.intern("<init>")
        let initFQName = abstractMutableListFQName + [initName]
        if symbols.lookup(fqName: initFQName) == nil {
            let initSymbol = symbols.define(
                kind: .constructor,
                name: initName,
                fqName: initFQName,
                declSite: nil,
                visibility: .protected,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(abstractMutableListSymbol, for: initSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: nil,
                    parameterTypes: [],
                    returnType: abstractMutableListType,
                    valueParameterSymbols: [],
                    valueParameterHasDefaultValues: [],
                    valueParameterIsVararg: [],
                    typeParameterSymbols: [typeParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: initSymbol
            )
        }

        return abstractMutableListSymbol
    }

}
