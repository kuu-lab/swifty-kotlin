@testable import CompilerCore
import Testing

@Suite
struct StringTrimMarginFunctionTests {
    @Test
    func testTrimMarginResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun stripDefaultMargin(s: String): String {
            return s.trimMargin()
        }

        fun stripGreaterThanMargin(s: String): String {
            return s.trimMargin(">")
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected String.trimMargin overloads to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }
}
