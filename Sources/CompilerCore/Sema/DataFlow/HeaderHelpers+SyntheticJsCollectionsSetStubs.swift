/// Synthetic Kotlin/JS collections `JsSet<E>` external class surface.
///
/// `JsSet<E>` extends `JsReadonlySet<out E>` and corresponds to the
/// JavaScript built-in `Set` type.  This stub is not wired into any
/// call path because the native-macOS target does not support
/// Kotlin/JS APIs — it exists only as an organisational record for
/// the cleanup sweep (CLEANUP-STUB-066).
extension DataFlowSemaPhase {
    func registerSyntheticJsCollectionsSetStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let pkg = ensurePackage(
            path: ["kotlin", "js", "collections"],
            symbols: symbols,
            interner: interner
        )
        let readonlySetSymbol = ensureJsReadonlySetForConversions(
            packageFQName: pkg,
            symbols: symbols,
            types: types,
            interner: interner
        ).symbol
        _ = ensureJsSetCollectionsType(
            packageFQName: pkg,
            readonlySetSymbol: readonlySetSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    func ensureJsSetCollectionsType(
        packageFQName: [InternedString],
        readonlySetSymbol: SymbolID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> (symbol: SymbolID, typeParameterSymbol: SymbolID) {
        let className = interner.intern("JsSet")
        let classFQName = packageFQName + [className]
        let classSymbol: SymbolID
        if let existing = symbols.lookup(fqName: classFQName),
           symbols.symbol(existing)?.kind == .class {
            classSymbol = existing
        } else {
            classSymbol = symbols.define(
                kind: .class,
                name: className,
                fqName: classFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .openType]
            )
        }
        if let packageSymbol = symbols.lookup(fqName: packageFQName) {
            symbols.setParentSymbol(packageSymbol, for: classSymbol)
        }
        symbols.insertFlags([.synthetic, .openType], for: classSymbol)
        appendJsCollectionsReadonlySetAnnotation(to: classSymbol, symbols: symbols)

        let typeParamName = interner.intern("E")
        let typeParamFQName = classFQName + [typeParamName]
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
        symbols.setParentSymbol(classSymbol, for: typeParamSymbol)

        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol,
            nullability: .nonNull
        )))
        let classType = types.make(.classType(ClassType(
            classSymbol: classSymbol,
            args: [.invariant(typeParamType)],
            nullability: .nonNull
        )))
        types.setNominalTypeParameterSymbols([typeParamSymbol], for: classSymbol)
        types.setNominalTypeParameterVariances([.invariant], for: classSymbol)
        symbols.setPropertyType(classType, for: classSymbol)
        symbols.setDirectSupertypes([readonlySetSymbol], for: classSymbol)
        types.setNominalDirectSupertypes([readonlySetSymbol], for: classSymbol)
        symbols.setSupertypeTypeArgs([.out(typeParamType)], for: classSymbol, supertype: readonlySetSymbol)
        types.setNominalSupertypeTypeArgs([.out(typeParamType)], for: classSymbol, supertype: readonlySetSymbol)

        return (classSymbol, typeParamSymbol)
    }
}
