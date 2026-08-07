@testable import CompilerCore
import Testing

/// STDLIB-TEXT-FN-112: `kotlin.text.String.trimIndent()`
///
/// `trimIndent()` removes the common minimal indent from multiline string
/// literals. KSP-302 wires it through bundled Kotlin source, so these tests
/// verify resolution and String return typing rather than a C runtime link.
@Suite
struct StringTrimIndentFunctionTests {
    @Test func testTrimIndentResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun main() {
            val literal: String = "    hello".trimIndent()
            val source: String = "  line"
            val dedented: String = source.trimIndent()
            val returnIsString: Int = "    abcde".trimIndent().length
            val chained: String = "  abc".trimIndent().trim()
        }
        """)

        try runSema(ctx)
        #expect(!(ctx.diagnostics.hasError), "resolve: \(ctx.diagnostics.diagnostics)")
    }

    @Test func testTrimIndentAcceptsNoArguments() throws {
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
}
