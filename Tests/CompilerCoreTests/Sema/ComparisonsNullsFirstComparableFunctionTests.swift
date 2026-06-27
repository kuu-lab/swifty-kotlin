@testable import CompilerCore
import XCTest

final class ComparisonsNullsFirstComparableFunctionTests: XCTestCase {
    func testNullsFirstComparableResolvesWithNoArgument() throws {
        let ctx = makeContextFromSource("""
        import kotlin.comparisons.nullsFirst

        fun makeComparator(): Comparator<Int?> {
            return nullsFirst()
        }
        """)
        try runSema(ctx)
        XCTAssertFalse(ctx.diagnostics.hasError, "resolve: \(ctx.diagnostics.diagnostics)")
    }

    func testNullsFirstComparableIsDistinctFromComparatorOverload() throws {
        let ctx = makeContextFromSource("""
        import kotlin.comparisons.nullsFirst
        import kotlin.comparisons.naturalOrder

        fun both(): Comparator<Int?> {
            val a: Comparator<Int?> = nullsFirst()
            val b: Comparator<Int?> = nullsFirst(naturalOrder<Int>())
            return a
        }
        """)
        try runSema(ctx)
        XCTAssertFalse(ctx.diagnostics.hasError, "resolve: \(ctx.diagnostics.diagnostics)")
    }
}
