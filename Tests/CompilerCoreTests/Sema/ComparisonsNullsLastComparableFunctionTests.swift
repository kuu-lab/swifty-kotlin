@testable import CompilerCore
import XCTest

final class ComparisonsNullsLastComparableFunctionTests: XCTestCase {
    func testNullsLastComparableFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlin.comparisons.nullsLast

        fun makeComparator(): Comparator<Int?> {
            return nullsLast<Int>()
        }
        """)
        try runSema(ctx)
        XCTAssertFalse(ctx.diagnostics.hasError, "resolve: \(ctx.diagnostics.diagnostics)")
    }

    func testNullsLastComparableLinksToNaturalRuntime() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "comparisons", "nullsLast"].map { interner.intern($0) }
        let symbols = sema.symbols.lookupAll(fqName: fqName)
        let nullsLastNaturalLinks = symbols.compactMap { sema.symbols.externalLinkName(for: $0) }
        XCTAssertTrue(
            nullsLastNaturalLinks.contains("kk_comparator_nulls_last_natural"),
            "nullsLast() (Comparable版) must link to kk_comparator_nulls_last_natural; found: \(nullsLastNaturalLinks)"
        )
    }
}
