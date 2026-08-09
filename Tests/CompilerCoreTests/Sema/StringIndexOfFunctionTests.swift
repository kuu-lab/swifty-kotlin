@testable import CompilerCore
import Testing

/// STDLIB-TEXT-FN-020: Validates that `kotlin.text.CharSequence.indexOf` resolves
/// through Sema for both the String-search overloads and the new Char overload.
/// Runtime link names involved:
/// - `kk_string_indexOf_flat` (single String argument)
/// - `kk_string_indexOf_from_flat` (String + startIndex)
/// - `kk_string_indexOf_ignoreCase_flat` (String + startIndex + ignoreCase)
/// - `kk_string_indexOf_char_flat` (Char + optional startIndex + optional ignoreCase)
@Suite
struct StringIndexOfFunctionTests {
    @Test func testIndexOfOverloadsResolveInSource() throws {
        let ctx = makeContextFromSource("""
        fun findToken(s: String): Int {
            return s.indexOf("token")
        }

        fun findFromOffset(s: String): Int {
            return s.indexOf("token", 3)
        }

        fun findCaseInsensitive(s: String): Int {
            return s.indexOf("Token", 0, true)
        }

        fun findChar(s: String): Int {
            return s.indexOf('x')
        }

        fun findCharFromOffset(s: String): Int {
            return s.indexOf('x', 2)
        }

        fun findCharCaseInsensitive(s: String): Int {
            return s.indexOf('X', 0, true)
        }
        """)

        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected CharSequence.indexOf overloads to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }
}
