extension DataFlowSemaPhase {
    func registerSyntheticStringEncodingStubs(context: SyntheticStringStubContext) -> SymbolID {
        let (symbols, types, interner) = (context.symbols, context.types, context.interner)
        let charSequenceSymbol = context.charSequenceSymbol
        // --- STDLIB-145: String.toByteArray / encodeToByteArray ---
        // These APIs are bundled Kotlin source in StringEncoding.kt.
        let javaMathPkg = ensurePackage(
            path: ["java", "math"],
            symbols: symbols,
            interner: interner
        )
        let javaMathPkgSymbol = symbols.lookup(fqName: javaMathPkg)
        let bigDecimalSymbol = ensureClassSymbol(
            named: "BigDecimal",
            in: javaMathPkg,
            symbols: symbols,
            interner: interner
        )
        if let javaMathPkgSymbol {
            symbols.setParentSymbol(javaMathPkgSymbol, for: bigDecimalSymbol)
        }
        let bigDecimalType = types.make(.classType(ClassType(
            classSymbol: bigDecimalSymbol, args: [], nullability: .nonNull
        )))
        symbols.setPropertyType(bigDecimalType, for: bigDecimalSymbol)

        // STDLIB-STR-125
        let kotlinPkg: [InternedString] = [interner.intern("kotlin")]
        let stringClassSymbol = ensureClassSymbol(
            named: "String",
            in: kotlinPkg,
            symbols: symbols,
            interner: interner
        )
        if let kotlinPkgSymbol = symbols.lookup(fqName: kotlinPkg) {
            symbols.setParentSymbol(kotlinPkgSymbol, for: stringClassSymbol)
        }
        types.stringClassSymbol = stringClassSymbol
        symbols.setDirectSupertypes([charSequenceSymbol], for: stringClassSymbol)
        types.setNominalDirectSupertypes([charSequenceSymbol], for: stringClassSymbol)
        // String constructors are source-backed in StringConstructors.kt. The
        // nominal shell and its CharSequence relationship remain here because
        // String is represented specially by the compiler and runtime.

        return stringClassSymbol
    }
}
