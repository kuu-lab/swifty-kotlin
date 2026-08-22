/// Synthetic stdlib top-level functions for kotlin.math (STDLIB-052).
/// All public kotlin.math APIs are now provided by bundled Kotlin source (Math.kt).
extension DataFlowSemaPhase {
    func registerSyntheticMathStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        // Primitive types are represented directly by TypeSystem, so Long has
        // no source declaration from which the Companion nominal can be
        // collected. Keep only the nominal anchor needed by bundled
        // Long.Companion extensions; the constants themselves are Kotlin
        // source-backed declarations.
        let kotlinPkg = ensurePackage(path: ["kotlin"], symbols: symbols, interner: interner)
        let longSymbol = ensureClassSymbol(
            named: "Long",
            in: kotlinPkg,
            symbols: symbols,
            interner: interner
        )
        if let kotlinPkgSymbol = symbols.lookup(fqName: kotlinPkg) {
            symbols.setParentSymbol(kotlinPkgSymbol, for: longSymbol)
        }
        ensureSyntheticLongCompanionSymbol(
            ownerSymbol: longSymbol,
            symbols: symbols,
            interner: interner
        )

        _ = ensureSyntheticPackageHierarchy(
            fqName: [interner.intern("kotlin"), interner.intern("math")],
            symbols: symbols
        )
    }

    private func ensureSyntheticLongCompanionSymbol(
        ownerSymbol: SymbolID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        if symbols.companionObjectSymbol(for: ownerSymbol) != nil {
            return
        }
        guard let ownerInfo = symbols.symbol(ownerSymbol) else { return }

        let companionName = interner.intern("Companion")
        let companionFQName = ownerInfo.fqName + [companionName]
        if let importedCompanion = symbols.lookupAll(fqName: companionFQName)
            .compactMap({ symbols.symbol($0) })
            .first(where: { $0.kind == .object || $0.kind == .class || $0.kind == .interface })
        {
            symbols.setParentSymbol(ownerSymbol, for: importedCompanion.id)
            symbols.setCompanionObjectSymbol(importedCompanion.id, for: ownerSymbol)
            return
        }

        let companionSymbol = symbols.define(
            kind: .object,
            name: companionName,
            fqName: companionFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .static]
        )
        symbols.setParentSymbol(ownerSymbol, for: companionSymbol)
        symbols.setCompanionObjectSymbol(companionSymbol, for: ownerSymbol)
    }
}
