#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct ComparisonsCompareValuesFunctionTests {
    @Test func testCompareValuesFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlin.comparisons.compareValues

        fun cmp(a: Int?, b: Int?): Int {
            return compareValues(a, b)
        }
        """)
        try runSema(ctx)
        #expect(!(ctx.diagnostics.hasError), "resolve: \(ctx.diagnostics.diagnostics)")
    }
}
#endif
