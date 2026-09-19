typealias SyntheticStringStubContext = (symbols: SymbolTable, types: TypeSystem, interner: StringInterner, charSequenceSymbol: SymbolID)
extension DataFlowSemaPhase {
    func registerSyntheticStringStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        _ = ensureKotlinTextPackage(symbols: symbols, interner: interner)
        let kotlinRootPkg = ensurePackage(path: ["kotlin"], symbols: symbols, interner: interner)
        // String is a compiler/runtime nominal shell. The bundled source owns
        // CharSequence whenever it is available; the fallback keeps bootstrap
        // contexts that intentionally omit bundled stdlib headers functional.
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
        let stringClassSymbol = registerSyntheticStringEncodingStubs(context: context)
        // String itself remains a compiler/runtime nominal shell, so retain a
        // Companion anchor for the source-backed extensions in StringFormat.kt.
        _ = ensureStringCompanionSymbol(
            ownerSymbol: stringClassSymbol,
            symbols: symbols,
            interner: interner
        )
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
