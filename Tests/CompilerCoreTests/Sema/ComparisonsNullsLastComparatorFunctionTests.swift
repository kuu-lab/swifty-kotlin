#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct ComparisonsNullsLastComparatorFunctionTests {
    @Test func testNullsLastComparatorFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlin.comparisons.nullsLast
        import kotlin.comparisons.naturalOrder

        fun makeComparator(): Comparator<Int?> {
            return nullsLast(naturalOrder<Int>())
        }
        """)
        try runSema(ctx)
        #expect(!(ctx.diagnostics.hasError), "resolve: \(ctx.diagnostics.diagnostics)")
    }
}
#endif
