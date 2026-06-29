@testable import CompilerCore
import Testing

/// STDLIB-TEXT-FN-042: Validates that `CharSequence.padStart(length, padChar)` resolves
/// through Sema for `String` receivers using both overloads.
/// - 1-arg overload (default padChar = ' ') resolves via bundled Kotlin stdlib.
/// - 2-arg overload (explicit padChar) resolves via bundled Kotlin stdlib.
@Suite
struct StringPadStartFunctionTests {
    @Test func testPadStartFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun leftPadDefault(s: String): String {
            return s.padStart(8)
        }

        fun leftPadWithChar(s: String): String {
            return s.padStart(8, '*')
        }

        fun leftPadShorterThanSource(): String {
            return "hello".padStart(3)
        }

        fun leftPadExpression(value: Int): String {
            return value.toString().padStart(6, '0')
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected padStart to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }
}
