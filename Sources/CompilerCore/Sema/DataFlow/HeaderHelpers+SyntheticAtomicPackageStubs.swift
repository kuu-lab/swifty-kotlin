
/// `kotlin.concurrent.atomics` package-level scaffolding — the
/// `@ExperimentalAtomicApi` annotation and the `MemoryOrder` enum —
/// extracted from the Atomic residual registration surface.
extension DataFlowSemaPhase {
    func registerSyntheticAtomicAnnotation(
        named name: String,
        in packageFQName: [InternedString],
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let annotationName = interner.intern(name)
        let fqName = packageFQName + [annotationName]
        guard symbols.lookup(fqName: fqName) == nil else { return }

        _ = symbols.define(
            kind: .annotationClass,
            name: annotationName,
            fqName: fqName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
    }

    func ensureAtomicMemoryOrderEnum(
        in pkg: [InternedString],
        symbols: SymbolTable,
        interner: StringInterner
    ) -> SymbolID {
        let name = interner.intern("MemoryOrder")
        let fqName = pkg + [name]
        if let existing = symbols.lookup(fqName: fqName) {
            return existing
        }
        let symbol = symbols.define(
            kind: .enumClass,
            name: name,
            fqName: fqName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        if let pkgSymbol = symbols.lookup(fqName: pkg), pkgSymbol != .invalid {
            symbols.setParentSymbol(pkgSymbol, for: symbol)
        }

        let entries = [
            "RELAXED",
            "ACQUIRE",
            "RELEASE",
            "ACQUIRE_RELEASE",
            "SEQUENTIALLY_CONSISTENT",
        ]
        for entry in entries {
            let entryName = interner.intern(entry)
            let entryFQName = fqName + [entryName]
            if symbols.lookup(fqName: entryFQName) != nil {
                continue
            }
            let entrySymbol = symbols.define(
                kind: .field,
                name: entryName,
                fqName: entryFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(symbol, for: entrySymbol)
        }
        return symbol
    }

    func setAtomicEnumEntryTypes(
        enumSymbol: SymbolID,
        enumType: TypeID,
        symbols: SymbolTable
    ) {
        guard let enumInfo = symbols.symbol(enumSymbol) else { return }
        let children = symbols.children(ofFQName: enumInfo.fqName)
        for child in children {
            guard let childSym = symbols.symbol(child),
                  childSym.kind == .field
            else {
                continue
            }
            if symbols.propertyType(for: child) == nil {
                symbols.setPropertyType(enumType, for: child)
            }
        }
    }
}
