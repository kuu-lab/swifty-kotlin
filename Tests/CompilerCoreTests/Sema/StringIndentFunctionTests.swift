@testable import CompilerCore
import XCTest

/// STDLIB-TEXT-FN-019: `kotlin.text.String.indent(n: Int)`
///
/// `indent(n)` は文字列の各行の先頭に n 個のスペースを追加（n > 0）、
/// または先頭から最大 -n 個のスペースを除去（n < 0）する拡張関数。
/// Sema が `kk_string_indent` / `kk_string_indent_default` に
/// 解決し、戻り値型が `String` になることを検証する。
final class StringIndentFunctionTests: XCTestCase {
    func testIndentWithNoArgumentsResolves() throws {
        let ctx = makeContextFromSource("""
        fun main() {
            val s: String = "hello".indent()
        }
        """)
        try runSema(ctx)
        XCTAssertFalse(ctx.diagnostics.hasError, "resolve: \(ctx.diagnostics.diagnostics)")
    }

    func testIndentWithIntArgumentResolves() throws {
        let ctx = makeContextFromSource("""
        fun main() {
            val s: String = "hello".indent(2)
        }
        """)
        try runSema(ctx)
        XCTAssertFalse(ctx.diagnostics.hasError, "resolve: \(ctx.diagnostics.diagnostics)")
    }

    func testIndentWithNegativeIntArgumentResolves() throws {
        let ctx = makeContextFromSource("""
        fun main() {
            val s: String = "  hello".indent(-2)
        }
        """)
        try runSema(ctx)
        XCTAssertFalse(ctx.diagnostics.hasError, "resolve: \(ctx.diagnostics.diagnostics)")
    }

    func testIndentReturnTypeIsString() throws {
        let ctx = makeContextFromSource("""
        fun main() {
            val n: Int = "  hello".indent(2).length
        }
        """)
        try runSema(ctx)
        XCTAssertFalse(ctx.diagnostics.hasError, "resolve: \(ctx.diagnostics.diagnostics)")
    }

    func testIndentChainableWithOtherStringMembers() throws {
        let ctx = makeContextFromSource("""
        fun main() {
            val s: String = "  abc".indent(2).trim()
        }
        """)
        try runSema(ctx)
        XCTAssertFalse(ctx.diagnostics.hasError, "resolve: \(ctx.diagnostics.diagnostics)")
    }

    func testIndentRejectsStringArgument() throws {
        let ctx = makeContextFromSource("""
        fun main() {
            val s = "hello".indent("  ")
        }
        """)
        try runSema(ctx)
        XCTAssertTrue(
            ctx.diagnostics.hasError,
            "expected error for String argument to indent, got: \(ctx.diagnostics.diagnostics)"
        )
    }
}
