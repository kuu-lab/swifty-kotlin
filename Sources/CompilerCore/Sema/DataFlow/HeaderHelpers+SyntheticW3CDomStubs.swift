/// Synthetic `org.w3c.dom` external interface stubs.
extension DataFlowSemaPhase {
    func registerSyntheticW3CDomStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let pkg = ensurePackage(
            path: ["org", "w3c", "dom"],
            symbols: symbols,
            interner: interner
        )
        registerItemArrayLike(
            packageFQName: pkg,
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    /// Register `org.w3c.dom.ItemArrayLike<out T>` as a synthetic external interface.
    ///
    /// Kotlin/JS stdlib declaration:
    ///   external interface ItemArrayLike<out T> { val length: Int; fun item(index: Int): T? }
    ///
    /// Only the type surface (interface + covariant type parameter) is registered here.
    /// Members (`length`, `item`) are omitted until a downstream consumer requires them.
    private func registerItemArrayLike(
        packageFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let interfaceName = interner.intern("ItemArrayLike")
        let interfaceFQName = packageFQName + [interfaceName]
        let interfaceSymbol = ensureInterfaceSymbol(
            named: "ItemArrayLike",
            in: packageFQName,
            symbols: symbols,
            interner: interner
        )
        if let packageSymbol = symbols.lookup(fqName: packageFQName) {
            symbols.setParentSymbol(packageSymbol, for: interfaceSymbol)
        }

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
        symbols.setTypeParameterUpperBounds([types.nullableAnyType], for: typeParamSymbol)

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
    }
}
