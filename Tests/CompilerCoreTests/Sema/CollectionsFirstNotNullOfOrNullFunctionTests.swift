#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct CollectionsFirstNotNullOfOrNullFunctionTests {
    @Test func testFirstNotNullOfOrNullFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun firstPositive(xs: List<Int>): String? {
            return xs.firstNotNullOfOrNull { if (it > 0) it.toString() else null }
        }
        """)
        try runSema(ctx)
        #expect(!(ctx.diagnostics.hasError), "resolve: \(ctx.diagnostics.diagnostics)")
    }
}
#endif
