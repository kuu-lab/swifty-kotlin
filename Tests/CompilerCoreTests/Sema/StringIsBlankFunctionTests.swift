@testable import CompilerCore
import XCTest

/// STDLIB-TEXT-FN-027: Validates that `String.isBlank()` resolves through Sema
/// for representative receiver shapes (string literal, parameter, safe-call on
/// a nullable receiver, and the corresponding `isNotBlank` overload). The
/// extension is registered as a synthetic stub bound to the runtime helper
/// `kk_string_isBlank` and is also covered indirectly by the
/// `stdlib_string_ops` golden — this micro-test pins direct Sema invocation so
/// regressions surface independently.
final class StringIsBlankFunctionTests: XCTestCase {
    func testIsBlankFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun blankSpaces(): Boolean = "   ".isBlank()

        fun blankNewline(): Boolean = "\\n\\t".isBlank()

        fun notBlankLiteral(): Boolean = "kotlin".isBlank()

        fun blankFromVariable(s: String): Boolean {
            return s.isBlank()
        }

        fun blankFromNullableSafeCall(s: String?): Boolean? {
            return s?.isBlank()
        }

        fun notBlankFromVariable(s: String): Boolean {
            return s.isNotBlank()
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected isBlank to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }
}
