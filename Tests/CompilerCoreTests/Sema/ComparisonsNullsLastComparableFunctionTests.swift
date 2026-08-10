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

    // KSP-461: nullsLast() (Comparable版) is bundled Kotlin source and delegates to
    // naturalOrder(); no runtime entry point may remain.
    @Test func testNullsLastComparableIsSourceBacked() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "comparisons", "nullsLast"].map { interner.intern($0) }
        let symbols = sema.symbols.lookupAll(fqName: fqName)
        let links = symbols.compactMap { sema.symbols.externalLinkName(for: $0) }
        #expect(links.isEmpty, "nullsLast must not keep runtime links; found: \(links)")
        let hasNoArgOverload = symbols.contains { symbolID in
            sema.symbols.functionSignature(for: symbolID)?.parameterTypes.isEmpty == true
        }
        #expect(hasNoArgOverload, "nullsLast() (Comparable版) must be registered from bundled stdlib source")
    }
}
#endif
