@testable import CompilerCore
import Testing

/// STDLIB-TEXT-FN-081: Validates that `CharSequence.takeLastWhile(predicate)` resolves
/// through Sema for `String` receivers. The synthetic stub links to `kk_string_takeLastWhile`.
@Suite
struct StringTakeLastWhileFunctionTests {
    @Test func testTakeLastWhileWithSimpleLambda() throws {
        let ctx = makeContextFromSource("""
        fun trailingLetters(s: String): String {
            return s.takeLastWhile { it.isLetter() }
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "resolve: \(ctx.diagnostics.diagnostics)")
    }

    @Test func testTakeLastWhileOnStringLiteral() throws {
        let ctx = makeContextFromSource("""
        fun trailDigits(): String {
            return "abc123".takeLastWhile { it.isDigit() }
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "resolve: \(ctx.diagnostics.diagnostics)")
    }

    @Test func testTakeLastWhileReturnTypeIsString() throws {
        let ctx = makeContextFromSource("""
        fun trailingLower(s: String): String {
            return s.takeLastWhile { it.isLowerCase() }
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "resolve: \(ctx.diagnostics.diagnostics)")
    }

    @Test func testTakeLastWhileChainedAfterTransform() throws {
        let ctx = makeContextFromSource("""
        fun trimmedSuffix(s: String): String {
            return s.trim().takeLastWhile { it != ' ' }
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "resolve: \(ctx.diagnostics.diagnostics)")
    }
}
