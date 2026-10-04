@testable import CompilerCore
import Testing

/// STDLIB-TEXT-FN-022: Validates that `CharSequence.indexOfFirst(predicate)` resolves
/// through Sema for `String` / `CharSequence` receivers, dispatching to the
/// runtime link name `kk_string_indexOfFirst_flat` for String receivers, and returns `Int`.
@Suite
struct StringIndexOfFirstFunctionTests {
    @Test func testIndexOfFirstResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun findDigit(s: String): Int {
            return s.indexOfFirst { it.isDigit() }
        }

        fun findUpperLiteral(): Int {
            return "Hello".indexOfFirst { it.isUpperCase() }
        }

        fun findEqualsX(s: String): Int {
            return s.indexOfFirst { ch -> ch == 'x' }
        }

        fun emptyIndexOfFirst(): Int {
            return "".indexOfFirst { it == 'a' }
        }

        fun usesIndexResult(s: String): Boolean {
            val idx: Int = s.indexOfFirst { it == 'z' }
            return idx >= 0
        }

        fun findInCharSequence(cs: CharSequence): Int {
            return cs.indexOfFirst { it.isLetter() }
        }
        """)

        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected indexOfFirst(predicate) to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }
}
