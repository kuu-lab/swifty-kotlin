import Foundation

/// Synthetic `org.w3c.dom.ItemArrayLike<T>` external interface surface.
///
/// `ItemArrayLike<T>` is a Kotlin/JS DOM external interface that represents
/// array-like objects (e.g. `NodeList`, `HTMLCollection`) that expose an
/// indexed `item(index: Int): T?` accessor and an integer `length` property.
extension DataFlowSemaPhase {
    func registerSyntheticW3cDomItemArrayLikeStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let pkg = ensurePackage(
            path: ["org", "w3c", "dom"],
            symbols: symbols,
            interner: interner
        )
        let itemArrayLike = ensureItemArrayLikeInterface(
            packageFQName: pkg,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerItemArrayLikeAsList(
            packageFQName: pkg,
            packageSymbol: symbols.lookup(fqName: pkg),
            itemArrayLikeSymbol: itemArrayLike.symbol,
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    /// Returns the symbol and type-parameter symbol for `ItemArrayLike<T>`,
    /// defining them if they have not yet been registered.
    func ensureItemArrayLikeInterface(
        packageFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> (symbol: SymbolID, typeParameterSymbol: SymbolID) {
        let interfaceSymbol = ensureInterfaceSymbol(
            named: "ItemArrayLike",
            in: packageFQName,
            symbols: symbols,
            interner: interner
        )
        if let packageSymbol = symbols.lookup(fqName: packageFQName) {
            symbols.setParentSymbol(packageSymbol, for: interfaceSymbol)
        }

        let interfaceFQName = packageFQName + [interner.intern("ItemArrayLike")]
        let typeParamName = interner.intern("T")
        let typeParamFQName = interfaceFQName + [typeParamName]
        let typeParamSymbol: SymbolID
        if let existing = symbols.lookup(fqName: typeParamFQName),
           symbols.symbol(existing)?.kind == .typeParameter {
            typeParamSymbol = existing
        } else {
            typeParamSymbol = symbols.define(
                kind: .typeParameter,
                name: typeParamName,
                fqName: typeParamFQName,
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
        }
        symbols.setParentSymbol(interfaceSymbol, for: typeParamSymbol)

        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol,
            nullability: .nonNull
        )))
        let interfaceType = types.make(.classType(ClassType(
            classSymbol: interfaceSymbol,
            args: [.out(typeParamType)],
            nullability: .nonNull
        )))
        types.setNominalTypeParameterSymbols([typeParamSymbol], for: interfaceSymbol)
        types.setNominalTypeParameterVariances([.out], for: interfaceSymbol)
        symbols.setPropertyType(interfaceType, for: interfaceSymbol)

        return (interfaceSymbol, typeParamSymbol)
    }

    private func registerItemArrayLikeAsList(
        packageFQName: [InternedString],
        packageSymbol: SymbolID?,
        itemArrayLikeSymbol: SymbolID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let functionName = interner.intern("asList")
        let functionFQName = packageFQName + [functionName]
        let typeParameterName = interner.intern("T")
        let typeParameterFQName = functionFQName + [typeParameterName]
        let typeParameterSymbol: SymbolID
        if let existing = symbols.lookup(fqName: typeParameterFQName),
           symbols.symbol(existing)?.kind == .typeParameter {
            typeParameterSymbol = existing
        } else {
            typeParameterSymbol = symbols.define(
                kind: .typeParameter,
                name: typeParameterName,
                fqName: typeParameterFQName,
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
        }
        symbols.setTypeParameterUpperBounds([types.anyType], for: typeParameterSymbol)
        let elementType = types.make(.typeParam(TypeParamType(
            symbol: typeParameterSymbol,
            nullability: .nonNull
        )))
        let receiverType = types.make(.classType(ClassType(
            classSymbol: itemArrayLikeSymbol,
            args: [.out(elementType)],
            nullability: .nonNull
        )))

        let collectionsPkg = ensurePackage(
            path: ["kotlin", "collections"],
            symbols: symbols,
            interner: interner
        )
        guard let listSymbol = symbols.lookup(fqName: collectionsPkg + [interner.intern("List")]) else {
            return
        }
        let returnType = types.make(.classType(ClassType(
            classSymbol: listSymbol,
            args: [.out(elementType)],
            nullability: .nonNull
        )))

        if symbols.lookupAll(fqName: functionFQName).contains(where: { symbolID in
            guard symbols.symbol(symbolID)?.kind == .function,
                  let signature = symbols.functionSignature(for: symbolID)
            else {
                return false
            }
            return signature.receiverType == receiverType
                && signature.parameterTypes.isEmpty
                && signature.returnType == returnType
        }) {
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
        if let packageSymbol {
            symbols.setParentSymbol(packageSymbol, for: functionSymbol)
        }
        symbols.setParentSymbol(functionSymbol, for: typeParameterSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [],
                returnType: returnType,
                typeParameterSymbols: [typeParameterSymbol],
                typeParameterUpperBoundsList: [[types.anyType]],
                valueParameterSymbols: [],
                valueParameterHasDefaultValues: [],
                valueParameterIsVararg: []
            ),
            for: functionSymbol
        )
        symbols.setExternalLinkName("kk_dom_itemArrayLike_asList", for: functionSymbol)
    }
}
