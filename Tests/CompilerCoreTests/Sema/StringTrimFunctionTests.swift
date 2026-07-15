@testable import CompilerCore
import Testing

/// STDLIB-TEXT-FN-110: Validates that `kotlin.text.String.trim` resolves
/// through bundled Kotlin stdlib source for both the no-arg and predicate overloads.
@Suite
struct StringTrimFunctionTests {
    @Test
    func testTrimFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun trimDefault(s: String): String {
            return s.trim()
        }

        fun trimWithPredicate(s: String): String {
            return s.trim { it == 'x' }
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected trim to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }
}
