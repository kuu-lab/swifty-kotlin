@testable import CompilerCore
import Testing

/// STDLIB-TEXT-FN-112: `kotlin.text.String.trimIndent()`
///
/// `trimIndent()` は複数行文字列リテラルから共通の最小インデント
/// (スペース・タブ) を取り除く拡張関数。Sema が `kk_string_trimIndent`
/// 外部リンク名に解決し、戻り値型が `String` になることを検証する。
@Suite
struct StringTrimIndentFunctionTests {
    @Test
    func testTrimIndentOnStringLiteralResolves() throws {
        let ctx = makeContextFromSource("""
        fun main() {
            val s: String = "    hello".trimIndent()
        }
        """)
        try runSema(ctx)
        #expect(!(ctx.diagnostics.hasError), "resolve: \(ctx.diagnostics.diagnostics)")
    }

    @Test
    func testTrimIndentOnStringVariableResolves() throws {
        let ctx = makeContextFromSource("""
        fun main() {
            val source: String = "  line"
            val dedented: String = source.trimIndent()
        }
        """)
        try runSema(ctx)
        #expect(!(ctx.diagnostics.hasError), "resolve: \(ctx.diagnostics.diagnostics)")
    }

    @Test
    func testTrimIndentAcceptsNoArguments() throws {
        // Pass an unexpected positional argument; Sema should reject it.
        let ctx = makeContextFromSource("""
        fun main() {
            val s = "abc".trimIndent(1)
        }
        """)
        try runSema(ctx)
        #expect(
            ctx.diagnostics.hasError,
            "expected error for extra argument, got: \(ctx.diagnostics.diagnostics)"
        )
    }

    @Test
    func testTrimIndentReturnTypeIsString() throws {
        // The return must be a String so subsequent String members (length) resolve.
        let ctx = makeContextFromSource("""
        fun main() {
            val n: Int = "    abcde".trimIndent().length
        }
        """)
        try runSema(ctx)
        #expect(!(ctx.diagnostics.hasError), "resolve: \(ctx.diagnostics.diagnostics)")
    }

    @Test
    func testTrimIndentChainableWithOtherStringMembers() throws {
        // trimIndent() must return a String compatible with subsequent String APIs.
        let ctx = makeContextFromSource("""
        fun main() {
            val s: String = "  abc".trimIndent().trim()
        }
        """)
        try runSema(ctx)
        #expect(!(ctx.diagnostics.hasError), "resolve: \(ctx.diagnostics.diagnostics)")
    }
}
