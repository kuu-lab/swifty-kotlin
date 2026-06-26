extension DataFlowSemaPhase {
    func makeSequenceType(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        elementType: TypeID
    ) -> TypeID {
        let sequenceSymbol = ensureSequenceSymbol(
            symbols: symbols, types: types, interner: interner
        )
        return types.make(.classType(ClassType(
            classSymbol: sequenceSymbol,
            args: [.out(elementType)],
            nullability: .nonNull
        )))
    }

    func ensureSequenceSymbol(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> SymbolID {
        let sequenceName = interner.intern("Sequence")
        let sequenceFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("sequences"),
            sequenceName,
        ]
        if let existing = symbols.lookup(fqName: sequenceFQName) {
            return existing
        }
        // Ensure the kotlin.sequences package exists
        let sequencesPkg: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("sequences"),
        ]
        if symbols.lookup(fqName: sequencesPkg) == nil {
            _ = symbols.define(
                kind: .package,
                name: interner.intern("sequences"),
                fqName: sequencesPkg,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        let sym = symbols.define(
            kind: .interface,
            name: sequenceName,
            fqName: sequenceFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        // Register type parameter T for Sequence<T>
        let typeParamName = interner.intern("T")
        let typeParamFQName = sequenceFQName + [typeParamName]
        let typeParamSymbol = symbols.define(
            kind: .typeParameter,
            name: typeParamName,
            fqName: typeParamFQName,
            declSite: nil,
            visibility: .private,
            flags: []
        )
        types.setNominalTypeParameterSymbols([typeParamSymbol], for: sym)
        types.setNominalTypeParameterVariances([.out], for: sym)
        return sym
    }

    func makeIterableType(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        elementType: TypeID
    ) -> TypeID {
        let iterableSymbol = ensureIterableSymbol(
            symbols: symbols, types: types, interner: interner
        )
        return types.make(.classType(ClassType(
            classSymbol: iterableSymbol,
            args: [.out(elementType)],
            nullability: .nonNull
        )))
    }

    func makeCollectionType(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        elementType: TypeID
    ) -> TypeID {
        let collectionSymbol = ensureCollectionSymbol(
            symbols: symbols,
            types: types,
            interner: interner
        )
        return types.make(.classType(ClassType(
            classSymbol: collectionSymbol,
            args: [.out(elementType)],
            nullability: .nonNull
        )))
    }

    func ensureCollectionSymbol(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> SymbolID {
        let collectionName = interner.intern("Collection")
        let collectionFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            collectionName,
        ]
        if let existing = symbols.lookup(fqName: collectionFQName) {
            return existing
        }
        let collectionsPkg: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("collections"),
        ]
        if symbols.lookup(fqName: collectionsPkg) == nil {
            _ = symbols.define(
                kind: .package,
                name: interner.intern("collections"),
                fqName: collectionsPkg,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        let sym = symbols.define(
            kind: .interface,
            name: collectionName,
            fqName: collectionFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        let typeParamName = interner.intern("E")
        let typeParamFQName = collectionFQName + [typeParamName]
        let typeParamSymbol = symbols.define(
            kind: .typeParameter,
            name: typeParamName,
            fqName: typeParamFQName,
            declSite: nil,
            visibility: .private,
            flags: []
        )
        types.setNominalTypeParameterSymbols([typeParamSymbol], for: sym)
        types.setNominalTypeParameterVariances([.out], for: sym)
        return sym
    }

    func ensureIterableSymbol(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> SymbolID {
        let iterableName = interner.intern("Iterable")
        let iterableFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            iterableName,
        ]
        if let existing = symbols.lookup(fqName: iterableFQName) {
            return existing
        }
        // Ensure the kotlin.collections package exists
        let collectionsPkg: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("collections"),
        ]
        if symbols.lookup(fqName: collectionsPkg) == nil {
            _ = symbols.define(
                kind: .package,
                name: interner.intern("collections"),
                fqName: collectionsPkg,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        let sym = symbols.define(
            kind: .interface,
            name: iterableName,
            fqName: iterableFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        // Register type parameter T for Iterable<T>
        let typeParamName = interner.intern("T")
        let typeParamFQName = iterableFQName + [typeParamName]
        let typeParamSymbol = symbols.define(
            kind: .typeParameter,
            name: typeParamName,
            fqName: typeParamFQName,
            declSite: nil,
            visibility: .private,
            flags: []
        )
        types.setNominalTypeParameterSymbols([typeParamSymbol], for: sym)
        types.setNominalTypeParameterVariances([.out], for: sym)
        return sym
    }

    func makeNominalType(
        symbols: SymbolTable,
        types: TypeSystem,
        fqName: [InternedString]
    ) -> TypeID {
        if let symbol = symbols.lookup(fqName: fqName) {
            return types.make(.classType(ClassType(
                classSymbol: symbol,
                args: [],
                nullability: .nonNull
            )))
        }

        guard let name = fqName.last else {
            return types.anyType
        }

        var packagePath: [InternedString] = []
        for packageName in fqName.dropLast() {
            packagePath.append(packageName)
            if symbols.lookup(fqName: packagePath) == nil {
                _ = symbols.define(
                    kind: .package,
                    name: packageName,
                    fqName: packagePath,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic]
                )
            }
        }

        let symbol = symbols.define(
            kind: .class,
            name: name,
            fqName: fqName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        return types.make(.classType(ClassType(
            classSymbol: symbol,
            args: [],
            nullability: .nonNull
        )))
    }

    func ensureListSymbol(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> SymbolID {
        let collectionsPkg: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("collections"),
        ]
        if symbols.lookup(fqName: collectionsPkg) == nil {
            _ = symbols.define(
                kind: .package,
                name: interner.intern("collections"),
                fqName: collectionsPkg,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        let listName = interner.intern("List")
        let listFQName = collectionsPkg + [listName]
        if let existing = symbols.lookup(fqName: listFQName) {
            return existing
        }
        let interfaceSymbol = symbols.define(
            kind: .interface,
            name: listName,
            fqName: listFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        let typeParamName = interner.intern("E")
        let typeParamFQName = listFQName + [typeParamName]
        let typeParamSymbol = symbols.define(
            kind: .typeParameter,
            name: typeParamName,
            fqName: typeParamFQName,
            declSite: nil,
            visibility: .private,
            flags: []
        )
        types.setNominalTypeParameterSymbols([typeParamSymbol], for: interfaceSymbol)
        types.setNominalTypeParameterVariances([.out], for: interfaceSymbol)
        return interfaceSymbol
    }

}
