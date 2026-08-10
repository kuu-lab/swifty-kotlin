#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct ComparisonsNullsLastComparableFunctionTests {

    @Test
    func testComparisonsNullsLastComparableFunctionTestsInventory() throws {
        let sources: [String] = [
            """
            package sample0
            import kotlin.comparisons.nullsLast

            fun makeComparator(): Comparator<Int?> {
                return nullsLast<Int>()
            }
            """,
        ]
        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let interner = ctx.interner

            let path0 = paths[0]
            let path0Diagnostics = diagnosticsForPath(path0, in: ctx)
            #expect(
                !path0Diagnostics.contains(where: { $0.severity == .error }),
                "resolve: \(path0Diagnostics)"
            )

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

            // === testNullsLastComparableFunctionResolvesInSource ===
            do {

                let makeComparatorSymbol = try #require(sema.symbols.lookup(fqName: [
                    interner.intern("sample0"),
                    interner.intern("makeComparator"),
                ]))
                #expect(sema.symbols.functionSignature(for: makeComparatorSymbol) != nil)
            }
        }
    }

}
#endif
