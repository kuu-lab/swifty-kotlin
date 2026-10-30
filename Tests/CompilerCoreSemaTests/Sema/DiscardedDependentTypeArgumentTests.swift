@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct DiscardedDependentTypeArgumentTests {
    @Test
    func acceptsExplicitDependentTypeArgumentsWhenResultIsDiscarded() throws {
        let ctx = makeContextFromSource("""
        fun <U : Any, T : U> dependent(value: Any?): T = value as T
        fun main() {
            try { dependent<Any, String>(null); "NO_THROW" }
            catch (e: NullPointerException) { "NPE" }
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
    }

    @Test
    func stillRejectsExplicitDependentTypeArgumentsThatViolateBounds() throws {
        let ctx = makeContextFromSource("""
        fun <U : Any, T : U> dependent(value: Any?): T = value as T
        fun main() { dependent<String, Any>(null) }
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError, "Expected the invalid dependent bound to be rejected.")
    }
}
