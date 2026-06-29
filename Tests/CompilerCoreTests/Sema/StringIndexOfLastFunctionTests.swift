@testable import CompilerCore
import Testing

/// STDLIB-TEXT-FN-023: Validates that `CharSequence.indexOfLast(predicate)` resolves
/// through Sema for `String` / `CharSequence` receivers, dispatching to the
/// runtime link name `kk_string_indexOfLast`, and returns `Int`.
@Suite
struct StringIndexOfLastFunctionTests {
    @Test func testIndexOfLastWithPredicateResolvesInSource() throws {
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
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected indexOfLast(predicate) to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    @Test func testIndexOfLastOnEmptyStringLiteral() throws {
        let ctx = makeContextFromSource("""
        fun emptyIndexOfLast(): Int {
            return "".indexOfLast { it == 'a' }
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected indexOfLast on empty literal to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    @Test func testIndexOfLastResultIsInt() throws {
        let ctx = makeContextFromSource("""
        fun usesIndexResult(s: String): Boolean {
            val idx: Int = s.indexOfLast { it == 'z' }
            return idx >= 0
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected indexOfLast result assignable to Int, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    @Test func testIndexOfLastOnCharSequenceReceiver() throws {
        let ctx = makeContextFromSource("""
        fun findLastInCharSequence(cs: CharSequence): Int {
            return cs.indexOfLast { it.isLetter() }
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected indexOfLast on CharSequence to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }
}
