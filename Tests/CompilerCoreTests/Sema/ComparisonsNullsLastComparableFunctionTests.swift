#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct ComparisonsNullsLastComparableFunctionTests {
    private static nonisolated(unsafe) var _sharedSema: (SemaModule, StringInterner)?

    private func sharedSema() throws -> (SemaModule, StringInterner) {
        if let cached = Self._sharedSema { return cached }
        let pair = try makeSema()
        Self._sharedSema = pair
        return pair
    }

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
        let (sema, interner) = try sharedSema()
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
