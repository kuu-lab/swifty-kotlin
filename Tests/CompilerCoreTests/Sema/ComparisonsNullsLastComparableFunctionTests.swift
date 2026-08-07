#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct ComparisonsNullsLastComparableFunctionTests {

    @Test
    func testComparisonsNullsLastComparableFunctionTestsInventory() throws {
        let sources: [String] = [
            """
            fun noop() {}
            """,
        ]
        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let interner = ctx.interner
            _ = ctx

            // === testNullsLastComparableLinksToNaturalRuntime ===
            do {

                let fqName = ["kotlin", "comparisons", "nullsLast"].map { interner.intern($0) }
                let symbols = sema.symbols.lookupAll(fqName: fqName)
                let nullsLastNaturalLinks = symbols.compactMap { sema.symbols.externalLinkName(for: $0) }
                #expect(
                    nullsLastNaturalLinks.contains("kk_comparator_nulls_last_natural"),
                    "nullsLast() (Comparable版) must link to kk_comparator_nulls_last_natural; found: \(nullsLastNaturalLinks)"
                )
            }
        }
    }

    @Test
    func testNullsLastComparableFunctionResolvesInSource() throws {

        let ctx = makeContextFromSource("""
        import kotlin.comparisons.nullsLast

        fun makeComparator(): Comparator<Int?> {
            return nullsLast<Int>()
        }
        """)
        try runSema(ctx)
        #expect(!(ctx.diagnostics.hasError), "resolve: \(ctx.diagnostics.diagnostics)")
    }

}
#endif
