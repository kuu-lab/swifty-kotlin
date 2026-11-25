extension DataFlowSemaPhase {
    func registerSyntheticDurationStubs(
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let kotlinTimePkg = ensureDurationPackageHierarchy(
            symbols: symbols,
            interner: interner
        )

        _ = ensureSyntheticDurationUnitEnumClass(
            in: kotlinTimePkg,
            symbols: symbols,
            interner: interner
        )
        let durationSymbol = ensureClassSymbol(
            named: "Duration",
            in: kotlinTimePkg,
            symbols: symbols,
            interner: interner
        )
        _ = ensureSyntheticCompanionSymbol(
            ownerSymbol: durationSymbol,
            symbols: symbols,
            interner: interner
        )
    }

    private func ensureSyntheticDurationUnitEnumClass(
        in packageFQName: [InternedString],
        symbols: SymbolTable,
        interner: StringInterner
    ) -> SymbolID {
        let enumName = interner.intern("DurationUnit")
        let enumFQName = packageFQName + [enumName]
        let enumSymbol: SymbolID
        if let existing = symbols.lookup(fqName: enumFQName) {
            enumSymbol = existing
            if let packageSymbol = symbols.lookup(fqName: packageFQName), packageSymbol != .invalid {
                symbols.setParentSymbol(packageSymbol, for: existing)
            }
        } else {
            let symbol = symbols.define(
                kind: .enumClass,
                name: enumName,
                fqName: enumFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            if let packageSymbol = symbols.lookup(fqName: packageFQName), packageSymbol != .invalid {
                symbols.setParentSymbol(packageSymbol, for: symbol)
            }
            enumSymbol = symbol
        }

        return enumSymbol
    }

    private func ensureDurationPackageHierarchy(
        symbols: SymbolTable,
        interner: StringInterner
    ) -> [InternedString] {
        let kotlinName = interner.intern("kotlin")
        let timeName = interner.intern("time")
        let kotlinFQ: [InternedString] = [kotlinName]
        if symbols.lookup(fqName: kotlinFQ) == nil {
            _ = symbols.define(
                kind: .package, name: kotlinName, fqName: kotlinFQ,
                declSite: nil, visibility: .public, flags: [.synthetic]
            )
        }
        let kotlinTimeFQ: [InternedString] = [kotlinName, timeName]
        if symbols.lookup(fqName: kotlinTimeFQ) == nil {
            _ = symbols.define(
                kind: .package, name: timeName, fqName: kotlinTimeFQ,
                declSite: nil, visibility: .public, flags: [.synthetic]
            )
        }
        return kotlinTimeFQ
    }
}
