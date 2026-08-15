/// Synthetic stdlib top-level functions for kotlin.math (STDLIB-052).
/// All public kotlin.math APIs are now provided by bundled Kotlin source (Math.kt).
extension DataFlowSemaPhase {
    func registerSyntheticMathStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        _ = ensureSyntheticPackageHierarchy(
            fqName: [interner.intern("kotlin"), interner.intern("math")],
            symbols: symbols
        )
    }
}
