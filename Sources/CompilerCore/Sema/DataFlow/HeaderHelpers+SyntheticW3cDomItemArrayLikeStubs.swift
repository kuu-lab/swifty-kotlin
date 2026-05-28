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
        _ = ensureItemArrayLikeInterface(
            packageFQName: pkg,
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
}
