@testable import CompilerCore
import Testing

/// STDLIB-TEXT-FN-063: `kotlin.text.CharSequence.reversed()`
///
/// `reversed()` returns a new string with the receiver scalars in reverse order.
/// Sema resolves it to `kk_string_reversed_flat` and keeps the result typed as
/// `String` (Kotlin's `CharSequence` implementation).
@Suite
struct StringReversedFunctionTests {
    @Test func testReversedResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun main() {
            val literal: String = "hello".reversed()
            val source: String = "kotlin"
            val flipped: String = source.reversed()
            val n: Int = "abcde".reversed().length
            val chained: String = "abc".reversed().reversed()
        }
        """)

        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "resolve: \(ctx.diagnostics.diagnostics)")
    }

    @Test func testReversedAcceptsNoArguments() throws {
        // Pass an unexpected positional argument; Sema should reject it.
        let ctx = makeContextFromSource("""
        fun main() {
            val s = "abc".reversed(1)
        }
        """)

        try runSema(ctx)
        #expect(
            ctx.diagnostics.hasError,
            "expected error for extra argument, got: \(ctx.diagnostics.diagnostics)"
        )
    }
}
