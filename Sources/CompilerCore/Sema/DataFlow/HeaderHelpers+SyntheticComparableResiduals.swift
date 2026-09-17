// KSP-697/KSP-700: compiler-side Comparable residuals.
//
// The nominal Comparable<in T> declaration, including `compareTo` itself, is
// bundled Kotlin source (Stdlib/kotlin/Comparable.kt, KSP-797); the interface
// lookup below is a `--no-stdlib`/precompiled-metadata fallback only. What
// remains here permanently (c) is compiler-metadata wiring with no Kotlin
// source equivalent: making the primitive types (Int, Double, ...) implement
// Comparable<Self> at the symbol-table level (setupPrimitiveComparableImplementations,
// HeaderHelpers+SyntheticComparableHelpers.swift — Int/Double/etc. are compiler
// intrinsics, not classes with a declarable supertype list) and the
// OpenEndRange/ClosedRange upper-bound patches, which belong to the Range
// module's own migration (KSP-714), not this one.
extension DataFlowSemaPhase {
    func registerSyntheticComparableStub(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinPkg: [InternedString] = [interner.intern("kotlin")]
        if symbols.lookup(fqName: kotlinPkg) == nil {
            _ = symbols.define(
                kind: .package,
                name: interner.intern("kotlin"),
                fqName: kotlinPkg,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }

        let comparableName = interner.intern("Comparable")
        let comparableFQName = kotlinPkg + [comparableName]
        let comparableSymbol: SymbolID = if let existing = symbols.lookup(fqName: comparableFQName) {
            existing
        } else {
            symbols.define(
                kind: .interface,
                name: comparableName,
                fqName: comparableFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }

        // Store in TypeSystem for use in isSubtype.
        types.comparableInterfaceSymbol = comparableSymbol
        types.setNominalTypeParameterVariances([.in], for: comparableSymbol)

        registerOpenEndRangeComparableUpperBound(
            comparableSymbol: comparableSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )
        setupPrimitiveComparableImplementations(
            symbols: symbols,
            types: types,
            interner: interner,
            comparableSymbol: comparableSymbol
        )
        patchSyntheticClosedRangeTypeParameterUpperBound(
            symbols: symbols,
            types: types,
            interner: interner
        )
    }
}
