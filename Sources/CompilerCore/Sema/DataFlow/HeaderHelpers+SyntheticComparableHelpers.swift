
extension DataFlowSemaPhase {

    func registerSyntheticPrimitiveCompanionAnchors(
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let kotlinPkg = ensurePackage(path: ["kotlin"], symbols: symbols, interner: interner)
        for name in ["Byte", "Long", "Short"] {
            let primitiveSymbol = ensureClassSymbol(
                named: name,
                in: kotlinPkg,
                symbols: symbols,
                interner: interner
            )
            if let kotlinPkgSymbol = symbols.lookup(fqName: kotlinPkg) {
                symbols.setParentSymbol(kotlinPkgSymbol, for: primitiveSymbol)
            }
            ensureSyntheticPrimitiveCompanionSymbol(
                ownerSymbol: primitiveSymbol,
                symbols: symbols,
                interner: interner
            )
        }
    }

    func setupPrimitiveComparableImplementations(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        comparableSymbol: SymbolID
    ) {
        let kotlinPkg = [interner.intern("kotlin")]

        let primitiveTypeNames = ["Byte", "Short", "Int", "Long", "Double", "Float", "Char", "Boolean", "UInt", "ULong", "UByte", "UShort"]

        for typeName in primitiveTypeNames {
            let primitiveSymbol = ensureClassSymbol(named: typeName, in: kotlinPkg, symbols: symbols, interner: interner)

            let primitiveType = types.make(.classType(ClassType(
                classSymbol: primitiveSymbol,
                args: [],
                nullability: .nonNull
            )))

            symbols.setDirectSupertypes([comparableSymbol], for: primitiveSymbol)
            types.setNominalDirectSupertypes([comparableSymbol], for: primitiveSymbol)
            symbols.setSupertypeTypeArgs([.in(primitiveType)], for: primitiveSymbol, supertype: comparableSymbol)
            types.setNominalSupertypeTypeArgs([.in(primitiveType)], for: primitiveSymbol, supertype: comparableSymbol)

            if typeName == "Double" || typeName == "Float" || typeName == "Int" || typeName == "UByte" || typeName == "UInt" || typeName == "ULong" || typeName == "UShort" {
                ensureSyntheticPrimitiveCompanionSymbol(
                    ownerSymbol: primitiveSymbol,
                    symbols: symbols,
                    interner: interner
                )
            }
        }
    }

    private func ensureSyntheticPrimitiveCompanionSymbol(
        ownerSymbol: SymbolID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        if symbols.companionObjectSymbol(for: ownerSymbol) != nil {
            return
        }
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }
        let companionName = interner.intern("Companion")
        let companionFQName = ownerInfo.fqName + [companionName]
        if let existing = symbols.lookupAll(fqName: companionFQName).first(where: { symbolID in
            guard let symbol = symbols.symbol(symbolID) else { return false }
            return symbol.kind == .object || symbol.kind == .class || symbol.kind == .interface
        }) {
            symbols.setParentSymbol(ownerSymbol, for: existing)
            symbols.setCompanionObjectSymbol(existing, for: ownerSymbol)
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
