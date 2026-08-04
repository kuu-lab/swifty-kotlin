@testable import CompilerCore
import Testing

/// STDLIB-TEXT-FN-080: Validates that `String.takeLast(n)` resolves through Sema for
/// `String` receivers. After KSP-405 it is bundled Kotlin source (StringTakeDrop.kt).
@Suite
struct StringTakeLastFunctionTests {
    @Test func testTakeLastResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun lastThree(): String {
            return "hello".takeLast(3)
        }

        fun suffix(s: String, n: Int): String {
            return s.takeLast(n)
        }

        fun lastHalf(s: String): String {
            return s.takeLast(s.length / 2)
        }

        fun greetingTail(name: String): String {
            return "Hello, ${name}!".takeLast(6)
        }
        """)

        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "resolve: \(ctx.diagnostics.diagnostics)")
    }
}
