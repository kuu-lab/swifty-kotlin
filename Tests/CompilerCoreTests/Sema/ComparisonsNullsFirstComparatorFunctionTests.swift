#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct ComparisonsNullsFirstComparatorFunctionTests {
    @Test func testNullsFirstComparatorFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlin.comparisons.nullsFirst
        import kotlin.comparisons.naturalOrder

        fun makeComparator(): Comparator<Int?> {
            return nullsFirst(naturalOrder<Int>())
        }
        """)
        try runSema(ctx)
        #expect(!(ctx.diagnostics.hasError), "resolve: \(ctx.diagnostics.diagnostics)")
    }
}
#endif
