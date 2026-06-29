@testable import CompilerCore
import Testing

/// STDLIB-TEXT-FN-022: Validates that `CharSequence.indexOfFirst(predicate)` resolves
/// through Sema for `String` / `CharSequence` receivers, dispatching to the
/// runtime link name `kk_string_indexOfFirst`, and returns `Int`.
@Suite
struct StringIndexOfFirstFunctionTests {
    @Test func testIndexOfFirstWithPredicateResolvesInSource() throws {
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
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected indexOfFirst(predicate) to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    @Test func testIndexOfFirstOnEmptyStringLiteral() throws {
        let ctx = makeContextFromSource("""
        fun emptyIndexOfFirst(): Int {
            return "".indexOfFirst { it == 'a' }
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected indexOfFirst on empty literal to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    @Test func testIndexOfFirstResultIsInt() throws {
        let ctx = makeContextFromSource("""
        fun usesIndexResult(s: String): Boolean {
            val idx: Int = s.indexOfFirst { it == 'z' }
            return idx >= 0
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected indexOfFirst result assignable to Int, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    @Test func testIndexOfFirstOnCharSequenceReceiver() throws {
        let ctx = makeContextFromSource("""
        fun findInCharSequence(cs: CharSequence): Int {
            return cs.indexOfFirst { it.isLetter() }
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected indexOfFirst on CharSequence to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }
}
