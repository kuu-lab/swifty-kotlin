@testable import CompilerCore
import Testing

/// STDLIB-TEXT-FN-028: Validates that `String.isEmpty()` resolves through Sema
/// for `String` / `CharSequence` receivers through bundled Kotlin source.
@Suite
struct StringIsEmptyFunctionTests {
    @Test func testIsEmptyFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun isStringEmpty(s: String): Boolean {
            return s.isEmpty()
        }

        fun isEmptyLiteral(): Boolean {
            return "".isEmpty()
        }

        fun isNonEmptyLiteral(): Boolean {
            return "hello".isEmpty()
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected isEmpty to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }
}
