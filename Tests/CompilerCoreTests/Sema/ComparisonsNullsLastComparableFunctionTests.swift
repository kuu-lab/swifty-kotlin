#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct ComparisonsNullsLastComparableFunctionTests {
    @Test func testNullsLastComparableFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlin.comparisons.nullsLast

        fun makeComparator(): Comparator<Int?> {
            return nullsLast<Int>()
        }
        """)
        try runSema(ctx)
        #expect(!(ctx.diagnostics.hasError), "resolve: \(ctx.diagnostics.diagnostics)")
    }

    /// KSP-461: nullsLast() is bundled Kotlin source, so no overload may keep a
    /// kk_* runtime link, and the no-argument Comparable form must exist.
    @Test func testNullsLastComparableIsSourceBacked() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "comparisons", "nullsLast"].map { interner.intern($0) }
        let symbols = sema.symbols.lookupAll(fqName: fqName)
        let links = symbols.compactMap { sema.symbols.externalLinkName(for: $0) }
        #expect(links.isEmpty, "nullsLast must not keep runtime links; found: \(links)")
        #expect(
            symbols.contains { symbol in
                sema.symbols.functionSignature(for: symbol).map {
                    $0.parameterTypes.isEmpty && $0.receiverType == nil
                } ?? false
            },
            "nullsLast<T : Comparable<T>>() must be registered from bundled stdlib source"
        )
    }
}
#endif
