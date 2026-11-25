typealias SyntheticStringStubContext = (symbols: SymbolTable, types: TypeSystem, interner: StringInterner, charSequenceSymbol: SymbolID)
extension DataFlowSemaPhase {
    func registerSyntheticStringStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        isJVMTarget: Bool = false
    ) {
        _ = ensureKotlinTextPackage(symbols: symbols, interner: interner)
        let kotlinRootPkg = ensurePackage(path: ["kotlin"], symbols: symbols, interner: interner)
        let charSequenceSymbol = symbols.lookup(
            fqName: kotlinRootPkg + [interner.intern("CharSequence")]
        ) ?? ensureInterfaceSymbol(
            named: "CharSequence",
            in: kotlinRootPkg,
            symbols: symbols,
            interner: interner
        )
        types.charSequenceInterfaceSymbol = charSequenceSymbol
        if let kotlinRootPkgSymbol = symbols.lookup(fqName: kotlinRootPkg) {
            symbols.setParentSymbol(kotlinRootPkgSymbol, for: charSequenceSymbol)
        }
        let context: SyntheticStringStubContext = (symbols, types, interner, charSequenceSymbol)
        let stringClassSymbol = registerSyntheticStringEncodingStubs(
            context: context,
            includeJavaMathBigDecimal: !isJVMTarget
        )
        _ = ensureStringCompanionSymbol(
            ownerSymbol: stringClassSymbol,
            symbols: symbols,
            interner: interner
        )
        // `String.Companion.format` is synthesized only for the JVM backend, whose
        // lowering emits `java/lang/String.format`. Native/Wasm resolve it from the
        // bundled `StringFormat.kt` extension instead, so registering a body-less
        // member here would shadow that working implementation.
        if isJVMTarget {
            registerStringCompanionFormatMembers(
                symbols: symbols,
                types: types,
                interner: interner,
                stringClassSymbol: stringClassSymbol
            )
        }
    }
    private func ensureKotlinTextPackage(
        symbols: SymbolTable,
        interner: StringInterner
    ) -> [InternedString] {
        let kotlinTextPkg: [InternedString] = [interner.intern("kotlin"), interner.intern("text")]
        if symbols.lookup(fqName: kotlinTextPkg) == nil {
            _ = symbols.define(
                kind: .package,
                name: interner.intern("text"),
                fqName: kotlinTextPkg,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        return kotlinTextPkg
    }
}
