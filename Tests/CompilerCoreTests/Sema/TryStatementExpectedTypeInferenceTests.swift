@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct TryStatementExpectedTypeInferenceTests {
    @Test
    func discardedTryResultDoesNotConstrainGenericCallsToUnit() throws {
        let ctx = makeContextFromSource("""
        fun main() {
            val empty = emptyArray<Int>()
            try { empty.reduceRight { x, y -> x + y } }
            catch (e: UnsupportedOperationException) { println(e.message) }
        }
        fun value(empty: Array<Int>): Int =
            try { empty.reduceRight { x, y -> x + y } }
            catch (e: UnsupportedOperationException) { 0 }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
    }
}
