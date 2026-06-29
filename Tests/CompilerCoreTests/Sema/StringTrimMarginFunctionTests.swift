@testable import CompilerCore
import Testing

@Suite
struct StringTrimMarginFunctionTests {
    @Test
    func testTrimMarginNoArgResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun stripDefaultMargin(s: String): String {
            return s.trimMargin()
        }
        """)
        try runSema(ctx)
        #expect(!(ctx.diagnostics.hasError), "resolve: \(ctx.diagnostics.diagnostics)")
    }

    @Test
    func testTrimMarginWithCustomPrefixResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun stripGreaterThanMargin(s: String): String {
            return s.trimMargin(">")
        }
        """)
        try runSema(ctx)
        #expect(!(ctx.diagnostics.hasError), "resolve: \(ctx.diagnostics.diagnostics)")
    }
}
