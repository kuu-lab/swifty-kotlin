@testable import CompilerCore
import Testing

/// STDLIB-SYSTEM-FN-001: `fun exitProcess(status: Int): Nothing` is resolvable
/// from `kotlin.system` and may appear in the body of a `Nothing`-returning function.
@Suite
struct SystemExitProcessFunctionTests {
    @Test
    func testExitProcessFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlin.system.exitProcess

        fun fail(): Nothing {
            exitProcess(1)
        }
        """)
        try runSema(ctx)
        #expect(!(ctx.diagnostics.hasError), "resolve: \(ctx.diagnostics.diagnostics)")
    }
}
