@testable import CompilerCore
import Testing

/// STDLIB-TEXT-FN-111: Validates that `String.trimEnd` resolves through bundled
/// Kotlin stdlib source for both the zero-argument and predicate overloads.
@Suite
struct StringTrimEndFunctionTests {
    @Test
    func testTrimEndFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun trimWhitespace(s: String): String {
            return s.trimEnd()
        }

        fun trimWithPredicate(s: String): String {
            return s.trimEnd { it == 'x' }
        }

        fun trimWithNamedPredicate(s: String): String {
            return s.trimEnd(predicate = { ch -> ch == ' ' || ch == '\\t' })
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected String.trimEnd overloads to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }
}
