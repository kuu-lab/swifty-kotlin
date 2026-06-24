#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct ComparisonsNaturalOrderFunctionTests {
    @Test func testNaturalOrderFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlin.comparisons.naturalOrder

        fun makeComparator(): Comparator<Int> {
            return naturalOrder<Int>()
        }
        """)
        try runSema(ctx)
        #expect(!(ctx.diagnostics.hasError), "resolve: \(ctx.diagnostics.diagnostics)")
    }
}
#endif
