#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct ComparisonsReverseOrderFunctionTests {
    @Test func testReverseOrderFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlin.comparisons.reverseOrder

        fun makeComparator(): Comparator<Int> {
            return reverseOrder<Int>()
        }
        """)
        try runSema(ctx)
        #expect(!(ctx.diagnostics.hasError), "resolve: \(ctx.diagnostics.diagnostics)")
    }
}
#endif
