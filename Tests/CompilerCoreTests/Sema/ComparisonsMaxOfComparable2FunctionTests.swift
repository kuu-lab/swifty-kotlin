#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct ComparisonsMaxOfComparable2FunctionTests {
    @Test func testMaxOfComparable2ArgFunctionResolvesInSource() throws {
        // Use String (a Kotlin built-in Comparable) so that the subtype
        // check primitive <: Comparable<primitive> is satisfied without
        // relying on user-defined generic supertype resolution.
        let ctx = makeContextFromSource("""
        import kotlin.comparisons.maxOf

        fun pickLatest(a: String, b: String): String {
            return maxOf(a, b)
        }
        """)
        try runSema(ctx)
        #expect(!(ctx.diagnostics.hasError), "Expected maxOf(a, b) Comparable 2-arg overload to resolve, got: \(ctx.diagnostics.diagnostics)")
    }
}
#endif
