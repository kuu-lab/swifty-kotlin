#if canImport(Testing)
@testable import CompilerCore
import Testing

/// STDLIB-TEXT-PROP-013: Validates that `kotlin.text.isLowerCase` resolves
/// through Sema as a Char extension (Kotlin spec defines it as `fun
/// Char.isLowerCase(): Boolean`). The runtime link name involved is
/// `kk_char_isLowerCase`.
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
