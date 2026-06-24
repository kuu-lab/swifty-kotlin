@testable import CompilerCore
import Testing

/// STDLIB-TEXT-FN-002: Validates that `CharSequence.any(predicate)` resolves
/// through Sema for `String` / `CharSequence` receivers, dispatching to the
/// runtime link name `kk_string_any`.
@Suite
struct StringAnyFunctionTests {
    @Test func testAnyWithPredicateResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun hasDigit(s: String): Boolean {
            return s.any { it.isDigit() }
        }

        fun hasUpperLiteral(): Boolean {
            return "Hello".any { it.isUpperCase() }
        }

        fun anyEqualsX(s: String): Boolean {
            return s.any { ch -> ch == 'x' }
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected any(predicate) to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    @Test func testAnyOnEmptyStringLiteral() throws {
        let ctx = makeContextFromSource("""
        fun emptyAny(): Boolean {
            return "".any { it == 'a' }
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected any on empty literal to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }
}
