#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct ComparisonsNullsFirstComparableFunctionTests {
    @Test
    func testNullsFirstComparableResolvesWithNoArgument() throws {
        let ctx = makeContextFromSource("""
        import kotlin.comparisons.nullsFirst

        fun makeComparator(): Comparator<Int?> {
            return nullsFirst()
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "resolve: \(ctx.diagnostics.diagnostics)")
    }

    @Test
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
        #expect(!ctx.diagnostics.hasError, "resolve: \(ctx.diagnostics.diagnostics)")
    }
}
#endif
