#if canImport(Testing)
@testable import CompilerCore
import Testing

/// STDLIB-TEXT-PROP-013 / KSP-661: Validates that `kotlin.text.isLowerCase`
/// resolves through Sema as a Char extension (`fun Char.isLowerCase(): Boolean`).
/// The predicate is implemented in bundled Kotlin (kotlin.text.CharPredicates).
@Suite
struct CharIsLowerCaseFunctionTests {
    @Test func testIsLowerCaseResolvesOnCharLiteralReceiver() throws {
        let ctx = makeContextFromSource("""
        fun isLowerOfLiteral(): Boolean {
            return 'a'.isLowerCase()
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected isLowerCase to type-check on a Char literal, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    @Test func testIsLowerCaseResolvesOnCharParameterReceiver() throws {
        let ctx = makeContextFromSource("""
        fun isLower(ch: Char): Boolean {
            return ch.isLowerCase()
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected isLowerCase to type-check on a Char parameter, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }
}
#endif
