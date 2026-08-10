@testable import CompilerCore
import Testing

/// STDLIB-TEXT-FN-019: `kotlin.text.String.indent(n: Int)`
///
/// `indent(n)` は文字列の各行の先頭に n 個のスペースを追加（n > 0）、
/// または先頭から最大 -n 個のスペースを除去（n < 0）する拡張関数。
/// Sema が `kk_string_indent` / `kk_string_indent_default` に
/// 解決し、戻り値型が `String` になることを検証する。
@Suite
struct StringIndentFunctionTests {
    @Test func testIndentResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun main() {
            val noArg: String = "hello".indent()
            val withInt: String = "hello".indent(2)
            val negative: String = "  hello".indent(-2)
            val returnIsString: Int = "  hello".indent(2).length
            val chained: String = "  abc".indent(2).trim()
        }
        """)

        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "resolve: \(ctx.diagnostics.diagnostics)")
    }

    @Test func testIndentRejectsStringArgument() throws {
        let ctx = makeContextFromSource("""
        fun main() {
            val s = "hello".indent("  ")
        }
        """)

        try runSema(ctx)
        #expect(
            ctx.diagnostics.hasError,
            "expected error for String argument to indent, got: \(ctx.diagnostics.diagnostics)"
        )
    }
}
