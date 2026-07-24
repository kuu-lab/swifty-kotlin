@testable import CompilerCore
import Testing

/// STDLIB-TEXT-FN-080: Validates that `String.takeLast(n)` resolves through Sema for
/// `String` receivers. After KSP-405 it is bundled Kotlin source (StringTakeDrop.kt).
@Suite
struct StringTakeLastFunctionTests {
    @Test func testTakeLastWithLiteralCount() throws {
        let ctx = makeContextFromSource("""
        fun lastThree(): String {
            return "hello".takeLast(3)
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "resolve: \(ctx.diagnostics.diagnostics)")
    }

    @Test func testTakeLastOnStringParameter() throws {
        let ctx = makeContextFromSource("""
        fun suffix(s: String, n: Int): String {
            return s.takeLast(n)
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "resolve: \(ctx.diagnostics.diagnostics)")
    }

    @Test func testTakeLastWithExpressionCount() throws {
        let ctx = makeContextFromSource("""
        fun lastHalf(s: String): String {
            return s.takeLast(s.length / 2)
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "resolve: \(ctx.diagnostics.diagnostics)")
    }

    @Test func testTakeLastChainedAfterTransform() throws {
        let ctx = makeContextFromSource("""
        fun greetingTail(name: String): String {
            return "Hello, ${name}!".takeLast(6)
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "resolve: \(ctx.diagnostics.diagnostics)")
    }
}
