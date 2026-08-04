@testable import CompilerCore
import Testing

@Suite
struct StringTrimStartFunctionTests {
    @Test
    func testTrimStartResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun stripLeadingWhitespace(s: String): String {
            return s.trimStart()
        }

        fun stripLeadingX(s: String): String {
            return s.trimStart { it == 'x' }
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected String.trimStart overloads to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }
}
