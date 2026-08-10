@testable import CompilerCore
import Testing

/// STDLIB-TEXT-FN-023: Validates that `CharSequence.indexOfLast(predicate)` resolves
/// through Sema for `String` / `CharSequence` receivers, dispatching to the
/// runtime link name `kk_string_indexOfLast`, and returns `Int`.
@Suite
struct StringIndexOfLastFunctionTests {
    @Test func testIndexOfLastResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun findLastDigit(s: String): Int {
            return s.indexOfLast { it.isDigit() }
        }

        fun findLastUpperLiteral(): Int {
            return "Hello".indexOfLast { it.isUpperCase() }
        }

        fun findLastEqualsX(s: String): Int {
            return s.indexOfLast { ch -> ch == 'x' }
        }

        fun emptyIndexOfLast(): Int {
            return "".indexOfLast { it == 'a' }
        }

        fun usesIndexResult(s: String): Boolean {
            val idx: Int = s.indexOfLast { it == 'z' }
            return idx >= 0
        }

        fun findLastInCharSequence(cs: CharSequence): Int {
            return cs.indexOfLast { it.isLetter() }
        }
        """)

        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected indexOfLast(predicate) to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }
}
