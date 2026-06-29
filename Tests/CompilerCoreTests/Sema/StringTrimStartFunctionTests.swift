@testable import CompilerCore
import Testing

@Suite
struct StringTrimStartFunctionTests {
    @Test
    func testTrimStartNoArgResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun stripLeadingWhitespace(s: String): String {
            return s.trimStart()
        }
        """)
        try runSema(ctx)
        #expect(!(ctx.diagnostics.hasError), "resolve: \(ctx.diagnostics.diagnostics)")
    }

    @Test
    func testTrimStartWithPredicateResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun stripLeadingX(s: String): String {
            return s.trimStart { it == 'x' }
        }
        """)
        try runSema(ctx)
        #expect(!(ctx.diagnostics.hasError), "resolve: \(ctx.diagnostics.diagnostics)")
    }
}
