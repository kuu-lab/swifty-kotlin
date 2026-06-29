@testable import CompilerCore
import Testing

/// STDLIB-TEXT-FN-063: `kotlin.text.CharSequence.reversed()`
///
/// `reversed()` は元の文字列を逆順にした新しい文字列を返す拡張関数。
/// Sema が `kk_string_reversed` 外部リンク名に解決し、戻り値型が
/// `String` (Kotlin の `CharSequence` 実装) になることを検証する。
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
