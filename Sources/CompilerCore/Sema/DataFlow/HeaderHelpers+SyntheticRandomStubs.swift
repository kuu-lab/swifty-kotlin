
/// Synthetic stdlib compat stubs for kotlin.random.Random (KSP-466).
///
/// The core Random API (nextInt/nextLong/nextFloat/nextDouble/nextBoolean/nextBits/
/// nextBytes, the Default companion, and the Random(seed) factories) now lives in
/// real Kotlin source (Sources/CompilerCore/Stdlib/kotlin/random/{Random,XorWowRandom,
/// URandom}.kt). This file only registers the surface that is *not yet* migrated:
///
/// - `Random` itself is registered here only as a bare `.class`-kind placeholder
///   symbol (matching the `Uuid` pattern in HeaderHelpers+SyntheticUuidStubs.swift):
///   the bundled Kotlin source's `abstract class Random` declaration reuses this
///   same symbol (matching kind avoids "duplicate declaration") once header
///   collection processes it, and this placeholder just needs to exist early
///   enough for the "Collections" bucket's `List.shuffled(random: Random)`
///   registration (which runs in the same pre-bundled pass) to resolve the type.
/// - Likewise, `java.util.Random` is registered here as a bare placeholder for
///   the same reason: `kotlin.random.asKotlinRandom()`'s receiver type is
///   `java.util.Random`, and that file (JavaRandomInterop.kt) sorts before
///   JavaUtilRandom.kt in bundled-source dictionary order, so without an early
///   placeholder the receiver type would not resolve yet when that file's
///   header is collected.
/// `asKotlinRandom` / `asJavaRandom` / `java.util.Random`'s own members are NOT
/// registered here: they are real Kotlin source (Sources/CompilerCore/Stdlib/
/// kotlin/random/JavaUtilRandom.kt, JavaRandomInterop.kt) — see that file's
/// header comment for why a native pointer-passthrough shim is no longer safe
/// now that kotlin.random.Random is a genuine compiled object instead of a
/// SeededRandomBox.
extension DataFlowSemaPhase {
    func registerSyntheticRandomStubs(
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let kotlinRandomPkg = ensureSyntheticPackageHierarchy(
            fqName: [interner.intern("kotlin"), interner.intern("random")],
            symbols: symbols
        )

        // Bare placeholder: kind must match the real `abstract class Random`
        // declared in bundled Kotlin source so header collection can enrich this
        // same symbol with real members instead of erroring on redeclaration.
        _ = ensureClassSymbol(
            named: "Random",
            in: kotlinRandomPkg,
            symbols: symbols,
            interner: interner
        )

        // Bare placeholder for java.util.Random; see the file header comment above.
        let javaUtilPkg = ensurePackage(
            path: ["java", "util"],
            symbols: symbols,
            interner: interner
        )
        _ = ensureClassSymbol(
            named: "Random",
            in: javaUtilPkg,
            symbols: symbols,
            interner: interner
        )

    }

}
