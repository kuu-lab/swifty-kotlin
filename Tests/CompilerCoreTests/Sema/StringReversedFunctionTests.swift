@testable import CompilerCore
import Testing

/// STDLIB-TEXT-FN-063: `kotlin.text.CharSequence.reversed()`
///
/// `reversed()` returns a new string with the receiver scalars in reverse order.
/// Sema resolves it to `kk_string_reversed_flat` and keeps the result typed as
/// `String` (Kotlin's `CharSequence` implementation).
@Suite
struct StringReversedFunctionTests {
    @Test func testReversedOnStringLiteralResolves() throws {
        let ctx = makeContextFromSource("""
        fun main() {
            val s: String = "hello".reversed()
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "resolve: \(ctx.diagnostics.diagnostics)")
    }

    @Test func testReversedOnStringVariableResolves() throws {
        let ctx = makeContextFromSource("""
        fun main() {
            val source: String = "kotlin"
            val flipped: String = source.reversed()
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

    @Test func testReversedReturnTypeIsString() throws {
        // The return must be a String so subsequent String members (length) resolve.
        let ctx = makeContextFromSource("""
        fun main() {
            val n: Int = "abcde".reversed().length
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "resolve: \(ctx.diagnostics.diagnostics)")
    }

    @Test func testReversedChainable() throws {
        // Reversing twice should still produce a String compatible with String APIs.
        let ctx = makeContextFromSource("""
        fun main() {
            val s: String = "abc".reversed().reversed()
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "resolve: \(ctx.diagnostics.diagnostics)")
    }
}
